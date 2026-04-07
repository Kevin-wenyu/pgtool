# Stat Sequences Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool stat sequences` command to show sequence usage statistics.

**Architecture:** Follow existing stat command pattern. SQL queries pg_sequences and pg_sequence for detailed stats.

**Tech Stack:** Bash, PostgreSQL SQL, psql

---

## File Structure

- **Create:** `sql/stat/sequences.sql`
- **Create:** `commands/stat/sequences.sh`
- **Modify:** `commands/stat/index.sh`
- **Create:** `tests/test_stat_sequences.sh`

---

### Task 1: Create SQL

**Files:**
- Create: `sql/stat/sequences.sql`

- [ ] **Step 1: Write SQL**

```sql
-- Sequence usage statistics
-- Output: schema, sequence, type, current, min, max, increment, cycle, owned_by

SELECT
    schemaname AS schema,
    sequencename AS sequence,
    data_type AS type,
    last_value AS current_value,
    start_value AS start_value,
    min_value AS minimum,
    max_value AS maximum,
    increment_by AS increment,
    cycle AS cycles,
    COALESCE(
        (SELECT 'owned by ' || c.relname || '.' || a.attname
         FROM pg_depend d
         JOIN pg_class c ON c.oid = d.refobjid
         JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = d.refobjsubid
         WHERE d.objid = (c.oid)
         AND d.deptype = 'a'),
        'unowned'
    ) AS owned_by
FROM pg_sequences
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, sequencename;
```

- [ ] **Step 2: Commit**

```bash
git add sql/stat/sequences.sql
git commit -m "feat(stat): add SQL for sequences statistics"
```

---

### Task 2: Create Command

**Files:**
- Create: `commands/stat/sequences.sh`

- [ ] **Step 1: Write script**

```bash
#!/bin/bash
# commands/stat/sequences.sh

pgtool_stat_sequences() {
    local -a opts=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_sequences_help
                return 0
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

    pgtool_info "序列使用统计"
    echo ""

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "stat" "sequences"); then
        pgtool_fatal "SQL文件未找到: stat/sequences"
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
    return $EXIT_SUCCESS
}

pgtool_stat_sequences_help() {
    cat <<EOF
序列使用统计

显示所有序列的当前值、范围、增量和拥有关系。

用法: pgtool stat sequences [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool stat sequences
  pgtool stat sequences --format=json
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/stat/sequences.sh
chmod +x commands/stat/sequences.sh
git commit -m "feat(stat): add sequences command implementation"
```

---

### Task 3: Register

- [ ] **Step 1: Update stat/index.sh**

Add "sequences:序列使用统计" to PGTOOL_STAT_COMMANDS and help.

- [ ] **Step 2: Commit**

```bash
git add commands/stat/index.sh
git commit -m "feat(stat): register sequences command"
```

---

### Task 4: Tests

**Files:**
- Create: `tests/test_stat_sequences.sh`

- [ ] **Step 1: Write tests**

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

test_files() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/stat/sequences.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/stat/sequences.sh ]]"
}

test_registered() {
    source "$PGTOOL_ROOT/commands/stat/index.sh"
    assert_contains "$PGTOOL_STAT_COMMANDS" "sequences"
}

echo ""
echo "Stat Sequences Tests:"
run_test "test_files" "Files exist"
run_test "test_registered" "Command registered"
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_stat_sequences.sh
chmod +x tests/test_stat_sequences.sh
git commit -m "test(stat): add tests for sequences command"
```
