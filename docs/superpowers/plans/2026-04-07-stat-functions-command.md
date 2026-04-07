# Stat Functions Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool stat functions` command to show function call statistics and execution time.

**Architecture:** Query pg_stat_user_functions for function statistics. Include call counts, total time, mean time.

**Tech Stack:** Bash, PostgreSQL SQL, psql

---

## File Structure

- **Create:** `sql/stat/functions.sql`
- **Create:** `commands/stat/functions.sh`
- **Modify:** `commands/stat/index.sh`
- **Create:** `tests/test_stat_functions.sh`

---

### Task 1: Create SQL

**Files:**
- Create: `sql/stat/functions.sql`

- [ ] **Step 1: Write SQL**

```sql
-- Function call statistics
-- Requires: track_functions = 'all' or 'pl'
-- Output: schema, function, calls, total_time, mean_time, stddev_time

SELECT
    schemaname AS schema,
    funcname AS function,
    calls,
    ROUND(total_exec_time::numeric, 3) AS total_time_ms,
    ROUND(mean_exec_time::numeric, 3) AS mean_time_ms,
    ROUND(stddev_exec_time::numeric, 3) AS stddev_time_ms,
    ROUND((total_exec_time / NULLIF(calls, 0))::numeric, 3) AS avg_time_ms
FROM pg_stat_user_functions
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY total_exec_time DESC
LIMIT 100;
```

- [ ] **Step 2: Commit**

```bash
git add sql/stat/functions.sql
git commit -m "feat(stat): add SQL for function statistics"
```

---

### Task 2: Create Command

**Files:**
- Create: `commands/stat/functions.sh`

- [ ] **Step 1: Write script**

```bash
#!/bin/bash
# commands/stat/functions.sh

pgtool_stat_functions() {
    local -a opts=()
    local limit=100

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_functions_help
                return 0
                ;;
            --limit)
                shift
                limit="$1"
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

    pgtool_info "函数调用统计"
    echo ""

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "stat" "functions"); then
        pgtool_fatal "SQL文件未找到: stat/functions"
    fi

    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Check if track_functions is enabled
    local track_funcs
    track_funcs=$(psql "${PGTOOL_CONN_OPTS[@]}" -tAc "SHOW track_functions;" 2>/dev/null)
    if [[ "$track_funcs" == "none" ]]; then
        pgtool_warn "track_functions is disabled. Statistics will be empty."
        pgtool_warn "Enable with: ALTER SYSTEM SET track_functions = 'all';"
    fi

    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        -v limit="$limit" \
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

pgtool_stat_functions_help() {
    cat <<EOF
函数调用统计

显示函数的调用次数和执行时间统计。
需要 track_functions 参数设置为 'all' 或 'pl'。

用法: pgtool stat functions [选项]

选项:
  -h, --help       显示帮助
      --limit NUM  显示条数限制 (默认: 100)

示例:
  pgtool stat functions
  pgtool stat functions --limit=50
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/stat/functions.sh
chmod +x commands/stat/functions.sh
git commit -m "feat(stat): add functions command implementation"
```

---

### Task 3: Register

- [ ] **Step 1: Update index.sh**

Add "functions:函数调用统计" to PGTOOL_STAT_COMMANDS.

- [ ] **Step 2: Commit**

```bash
git add commands/stat/index.sh
git commit -m "feat(stat): register functions command"
```

---

### Task 4: Tests

**Files:**
- Create: `tests/test_stat_functions.sh`

- [ ] **Step 1: Write tests**

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

test_files() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/stat/functions.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/stat/functions.sh ]]"
}

test_registered() {
    source "$PGTOOL_ROOT/commands/stat/index.sh"
    assert_contains "$PGTOOL_STAT_COMMANDS" "functions"
}

echo ""
echo "Stat Functions Tests:"
run_test "test_files" "Files exist"
run_test "test_registered" "Command registered"
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_stat_functions.sh
chmod +x tests/test_stat_functions.sh
git commit -m "test(stat): add tests for functions command"
```
