# Check Orphans Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool check orphans` command to find orphaned temporary tables, leftover objects from failed operations, and dangling references.

**Architecture:** Follow existing check command pattern. SQL queries identify objects without proper parent references or that should have been cleaned up.

**Tech Stack:** Bash, PostgreSQL SQL, psql

---

## File Structure

- **Create:** `sql/check/orphans.sql` - SQL to find orphaned objects
- **Create:** `commands/check/orphans.sh` - Command implementation
- **Modify:** `commands/check/index.sh` - Register command
- **Create:** `tests/test_check_orphans.sh` - Unit tests

---

### Task 1: Create SQL Query

**Files:**
- Create: `sql/check/orphans.sql`

- [ ] **Step 1: Write SQL**

Create `sql/check/orphans.sql`:
```sql
-- Check for orphaned objects in the database
-- Parameters: none
-- Output: object_type, schema, object_name, reason, status

-- Find orphaned temporary tables (older than 24 hours, likely dead connections)
WITH orphaned_temp_tables AS (
    SELECT
        'TEMP TABLE' AS object_type,
        schemaname AS schema_name,
        tablename AS object_name,
        'Temporary table from dead connection (age: ' || 
        EXTRACT(EPOCH FROM (NOW() - pg_stat_user_tables.last_vacuum))/3600 || ' hours)' AS reason,
        'WARNING' AS status
    FROM pg_stat_user_tables
    WHERE schemaname LIKE 'pg_temp%'
        OR (schemaname = 'pg_catalog' AND tablename LIKE 'pg_temp%')
        OR tablename LIKE 'tmp%'
        OR tablename LIKE 'temp%'
),
-- Find orphaned indexes (indexes on dropped tables - this shouldn't happen but check)
orphaned_indexes AS (
    SELECT
        'ORPHAN INDEX' AS object_type,
        n.nspname AS schema_name,
        c.relname AS object_name,
        'Index may be orphaned: ' || c.relname AS reason,
        'WARNING' AS status
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'I'  -- partitioned indexes
        AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
        AND NOT EXISTS (
            SELECT 1 FROM pg_inherits i WHERE i.inhparent = c.oid
        )
),
-- Find tables with no primary key (potential orphans if used as FK target)
tables_no_pk AS (
    SELECT
        'TABLE NO PK' AS object_type,
        c.relnamespace::regnamespace::text AS schema_name,
        c.relname AS object_name,
        'Table without primary key' AS reason,
        'INFO' AS status
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
        AND NOT EXISTS (
            SELECT 1 FROM pg_constraint con
            WHERE con.conrelid = c.oid AND con.contype = 'p'
        )
        AND c.reltuples > 0  -- Only for tables with data
),
-- Find idle prepared transactions
idle_prepared AS (
    SELECT
        'PREPARED XACT' AS object_type,
        database AS schema_name,
        transaction AS object_name,
        'Prepared transaction idle for ' || 
        EXTRACT(EPOCH FROM (NOW() - prepared))/3600 || ' hours' AS reason,
        CASE
            WHEN EXTRACT(EPOCH FROM (NOW() - prepared)) > 86400 THEN 'CRITICAL'
            WHEN EXTRACT(EPOCH FROM (NOW() - prepared)) > 3600 THEN 'WARNING'
            ELSE 'OK'
        END AS status
    FROM pg_prepared_xacts
    WHERE prepared < NOW() - INTERVAL '1 hour'
),
-- Find orphaned replication slots (if pg_replication_slots exists)
orphaned_slots AS (
    SELECT
        'REPL SLOT' AS object_type,
        slot_name AS schema_name,
        plugin AS object_name,
        'Inactive replication slot (active_pid: ' || COALESCE(active_pid::text, 'null') || ')' AS reason,
        CASE WHEN active = false THEN 'WARNING' ELSE 'OK' END AS status
    FROM pg_replication_slots
    WHERE active = false
)
SELECT * FROM orphaned_temp_tables
UNION ALL
SELECT * FROM orphaned_indexes
UNION ALL
SELECT * FROM tables_no_pk
UNION ALL
SELECT * FROM idle_prepared
UNION ALL
SELECT * FROM orphaned_slots
ORDER BY 
    CASE status 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'WARNING' THEN 2 
        WHEN 'INFO' THEN 3 
        ELSE 4 
    END,
    object_type,
    schema_name,
    object_name;
```

- [ ] **Step 2: Commit**

```bash
git add sql/check/orphans.sql
git commit -m "feat(check): add SQL for orphans check command"
```

---

### Task 2: Create Command Script

**Files:**
- Create: `commands/check/orphans.sh`

- [ ] **Step 1: Write script**

```bash
#!/bin/bash
# commands/check/orphans.sh

pgtool_check_orphans() {
    local -a opts=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_orphans_help
                return 0
                ;;
            --include-info)
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "检查孤儿对象..."
    echo ""

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "orphans"); then
        pgtool_fatal "SQL文件未找到: check/orphans"
    fi

    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    if echo "$result" | grep -q "CRITICAL"; then
        return 2
    elif echo "$result" | grep -q "WARNING"; then
        return 1
    fi

    return $EXIT_SUCCESS
}

pgtool_check_orphans_help() {
    cat <<EOF
检查孤儿对象

检查临时表、孤立索引、空闲预提交事务等孤儿对象。

用法: pgtool check orphans [选项]

选项:
  -h, --help       显示帮助
  --include-info   包含INFO级别的问题

示例:
  pgtool check orphans
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/check/orphans.sh
chmod +x commands/check/orphans.sh
git commit -m "feat(check): add orphans command implementation"
```

---

### Task 3: Register Command

- [ ] **Step 1: Update index.sh**

Add "orphans" to PGTOOL_CHECK_COMMANDS and help.

- [ ] **Step 2: Commit**

```bash
git add commands/check/index.sh
git commit -m "feat(check): register orphans command"
```

---

### Task 4: Create Tests

**Files:**
- Create: `tests/test_check_orphans.sh`

- [ ] **Step 1: Write tests**

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

test_sql_exists() { assert_true "[[ -f $PGTOOL_ROOT/sql/check/orphans.sql ]]"; }
test_cmd_exists() { assert_true "[[ -f $PGTOOL_ROOT/commands/check/orphans.sh ]]"; }
test_registered() {
    source "$PGTOOL_ROOT/commands/check/index.sh"
    assert_contains "$PGTOOL_CHECK_COMMANDS" "orphans"
}

echo ""
echo "Check Orphans Tests:"
run_test "test_sql_exists" "SQL file exists"
run_test "test_cmd_exists" "Command script exists"
run_test "test_registered" "Command registered"
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_check_orphans.sh
chmod +x tests/test_check_orphans.sh
git commit -m "test(check): add tests for orphans command"
```
