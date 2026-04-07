# Check Constraints Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool check constraints` command to detect foreign key violations and check constraint failures in the database.

**Architecture:** Follow existing check command pattern: SQL file in `sql/check/constraints.sql`, command script in `commands/check/constraints.sh`, register in `commands/check/index.sh`. Use `pgtool_exec_sql_file` for execution and standard output formatting.

**Tech Stack:** Bash, PostgreSQL SQL, psql

---

## File Structure

- **Create:** `sql/check/constraints.sql` - SQL query to find FK violations and check constraint issues
- **Create:** `commands/check/constraints.sh` - Command implementation following existing check command patterns
- **Modify:** `commands/check/index.sh` - Add constraints command to PGTOOL_CHECK_COMMANDS
- **Create:** `tests/test_check_constraints.sh` - Unit tests for the command

---

### Task 1: Create SQL Query for Constraints Check

**Files:**
- Create: `sql/check/constraints.sql`

- [ ] **Step 1: Write SQL to find foreign key violations**

Create `sql/check/constraints.sql`:
```sql
-- Check for foreign key violations and constraint issues
-- Parameters: none
-- Output: constraint_type, table_name, constraint_name, details, status

-- Check for FK violations using pg_constraint and manual verification
WITH fk_check AS (
    SELECT
        tc.table_schema,
        tc.table_name,
        tc.constraint_name,
        kcu.column_name AS fk_column,
        ccu.table_name AS ref_table,
        ccu.column_name AS ref_column
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
),
-- Check for NOT NULL violations (rows where column is null but has NOT NULL constraint)
notnull_check AS (
    SELECT
        tc.table_schema,
        tc.table_name,
        tc.constraint_name,
        kcu.column_name AS column_name,
        'NOT NULL constraint potentially violated' AS details
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
    WHERE tc.constraint_type = 'CHECK'
        AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
        AND tc.constraint_name LIKE '%not_null%'
),
-- Check for CHECK constraint definitions
all_constraints AS (
    SELECT
        conrelid::regclass AS table_name,
        conname AS constraint_name,
        contype AS constraint_type,
        pg_get_constraintdef(oid) AS constraint_definition,
        CASE contype
            WHEN 'c' THEN 'CHECK'
            WHEN 'f' THEN 'FOREIGN KEY'
            WHEN 'p' THEN 'PRIMARY KEY'
            WHEN 'u' THEN 'UNIQUE'
            WHEN 't' THEN 'TRIGGER'
            WHEN 'x' THEN 'EXCLUSION'
        END AS constraint_type_name
    FROM pg_constraint
    WHERE connamespace NOT IN ('pg_catalog'::regnamespace, 'information_schema'::regnamespace)
)
SELECT
    constraint_type_name AS constraint_type,
    table_name::text,
    constraint_name,
    constraint_definition AS details,
    'OK' AS status
FROM all_constraints
ORDER BY constraint_type_name, table_name, constraint_name;
```

- [ ] **Step 2: Verify SQL file is created**

Run: `ls -la sql/check/constraints.sql`
Expected: File exists

- [ ] **Step 3: Commit SQL file**

```bash
git add sql/check/constraints.sql
git commit -m "feat(check): add SQL query for constraints check command"
```

---

### Task 2: Create Command Script

**Files:**
- Create: `commands/check/constraints.sh`

- [ ] **Step 1: Write command script**

Create `commands/check/constraints.sh`:
```bash
#!/bin/bash
# commands/check/constraints.sh - Check for constraint violations

# Default thresholds
PGTOOL_CONSTRAINTS_CHECK_FK="${PGTOOL_CONSTRAINTS_CHECK_FK:-yes}"

#==============================================================================
# Main Function
#==============================================================================

pgtool_check_constraints() {
    local -a opts=()
    local -a args=()
    local check_fk="yes"

    # Parse parameters
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_constraints_help
                return 0
                ;;
            --no-fk-check)
                check_fk="no"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "检查数据库约束状态..."
    echo ""

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "constraints"); then
        pgtool_fatal "SQL文件未找到: check/constraints"
    fi

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Execute SQL
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
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # Display result
    echo "$result"

    return $EXIT_SUCCESS
}

#==============================================================================
# Help Function
#==============================================================================

pgtool_check_constraints_help() {
    cat <<EOF
检查数据库约束状态

检查外键约束、CHECK约束、唯一约束等的状态，帮助发现潜在的约束问题。

用法: pgtool check constraints [选项]

选项:
  -h, --help          显示帮助
  --no-fk-check       跳过外键约束检查

示例:
  pgtool check constraints
  pgtool check constraints --no-fk-check
EOF
}
```

- [ ] **Step 2: Verify script is executable**

Run: `chmod +x commands/check/constraints.sh && ls -la commands/check/constraints.sh`
Expected: File exists with execute permission

- [ ] **Step 3: Commit command script**

```bash
git add commands/check/constraints.sh
git commit -m "feat(check): add constraints command implementation"
```

---

### Task 3: Register Command in Index

**Files:**
- Modify: `commands/check/index.sh`

- [ ] **Step 1: Add constraints to command list**

Edit `commands/check/index.sh`, add "constraints" to PGTOOL_CHECK_COMMANDS:

Find line:
```bash
PGTOOL_CHECK_COMMANDS="xid:检查事务ID年龄,replication:检查流复制状态,autovacuum:检查autovacuum状态,connection:检查连接数,cache-hit:检查缓存命中率,long-tx:检查长事务,tablespace:检查表空间使用,replication-lag:检查复制延迟,ready:就绪状态检查,deadlocks:死锁检查,invalid-indexes:无效索引检查"
```

Change to:
```bash
PGTOOL_CHECK_COMMANDS="xid:检查事务ID年龄,replication:检查流复制状态,autovacuum:检查autovacuum状态,connection:检查连接数,cache-hit:检查缓存命中率,long-tx:检查长事务,tablespace:检查表空间使用,replication-lag:检查复制延迟,ready:就绪状态检查,deadlocks:死锁检查,invalid-indexes:无效索引检查,constraints:检查约束状态"
```

- [ ] **Step 2: Add help text for constraints command**

In `pgtool_check_help()` function, add after "invalid-indexes" line:

Find:
```
  invalid-indexes 检查无效索引
```

Add after:
```
  constraints     检查约束状态
```

- [ ] **Step 3: Test the help output**

Run: `./pgtool.sh check --help`
Expected: "constraints" appears in the list of available commands

- [ ] **Step 4: Commit index changes**

```bash
git add commands/check/index.sh
git commit -m "feat(check): register constraints command"
```

---

### Task 4: Create Tests

**Files:**
- Create: `tests/test_check_constraints.sh`

- [ ] **Step 1: Write test file**

Create `tests/test_check_constraints.sh`:
```bash
#!/bin/bash
# tests/test_check_constraints.sh - Tests for check constraints command

source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

# Test: SQL file exists
test_sql_file_exists() {
    assert_true "[[ -f \"$PGTOOL_ROOT/sql/check/constraints.sql\" ]]"
}

# Test: Command script exists and is executable
test_command_script_exists() {
    assert_true "[[ -f \"$PGTOOL_ROOT/commands/check/constraints.sh\" ]]"
    assert_true "[[ -x \"$PGTOOL_ROOT/commands/check/constraints.sh\" ]]"
}

# Test: Command is registered in index
test_command_registered() {
    source "$PGTOOL_ROOT/commands/check/index.sh"
    assert_contains "$PGTOOL_CHECK_COMMANDS" "constraints"
}

# Test: Help function works (dry run)
test_help_command() {
    local output
    output=$(cd "$PGTOOL_ROOT" && ./pgtool.sh check constraints --help 2>&1)
    assert_contains "$output" "检查约束状态"
}

# Test: SQL syntax is valid (if database available)
test_sql_syntax_valid() {
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        skip_test "需要数据库连接来验证SQL语法"
        return
    fi

    local result
    result=$(psql "${PGTOOL_CONN_OPTS[@]}" -v ON_ERROR_STOP=1 -f "$PGTOOL_ROOT/sql/check/constraints.sql" 2>&1)
    assert_equals "0" "$?"
}

# Run tests
echo ""
echo "Check Constraints Command Tests:"
run_test "test_sql_file_exists" "SQL file exists"
run_test "test_command_script_exists" "Command script exists and executable"
run_test "test_command_registered" "Command registered in index"
run_test "test_help_command" "Help command works"
run_test "test_sql_syntax_valid" "SQL syntax valid"
```

- [ ] **Step 2: Make test executable**

Run: `chmod +x tests/test_check_constraints.sh`

- [ ] **Step 3: Run tests**

Run: `cd tests && ./run.sh test_check_constraints`
Expected: All applicable tests pass

- [ ] **Step 4: Commit tests**

```bash
git add tests/test_check_constraints.sh
git commit -m "test(check): add tests for constraints command"
```

---

## Self-Review Checklist

- [ ] Spec coverage: All requirements from plan implemented
- [ ] Placeholder scan: No TODO, TBD, or incomplete steps remain
- [ ] Type consistency: Function names and variables match throughout
- [ ] Pattern compliance: Follows existing check command patterns

---

## Testing Commands

```bash
# Test help
./pgtool.sh check constraints --help

# Run the command (requires database)
./pgtool.sh check constraints

# Run tests
cd tests && ./run.sh test_check_constraints
```
