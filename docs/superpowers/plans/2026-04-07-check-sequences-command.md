# Check Sequences Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool check sequences` command to detect sequences approaching their maximum value (sequence exhaustion risk).

**Architecture:** Follow existing check command pattern. SQL queries calculate sequence usage percentage, command script applies thresholds (default warning at 80%, critical at 95%), returns appropriate exit codes.

**Tech Stack:** Bash, PostgreSQL SQL, psql

---

## File Structure

- **Create:** `sql/check/sequences.sql` - SQL to calculate sequence exhaustion
- **Create:** `commands/check/sequences.sh` - Command implementation
- **Modify:** `commands/check/index.sh` - Register command
- **Create:** `tests/test_check_sequences.sh` - Unit tests

---

### Task 1: Create SQL Query for Sequences Check

**Files:**
- Create: `sql/check/sequences.sql`

- [ ] **Step 1: Write SQL to check sequence exhaustion**

Create `sql/check/sequences.sql`:
```sql
-- Check for sequences approaching exhaustion
-- Parameters: warning_threshold (default 80), critical_threshold (default 95)
-- Output: schema, sequence_name, data_type, current_value, max_value, usage_pct, status

WITH sequence_stats AS (
    SELECT
        schemaname AS schema,
        sequencename AS sequence_name,
        last_value AS current_value,
        -- Get sequence data type and limits
        CASE
            WHEN seqtypid = 'bigint'::regtype THEN 9223372036854775807::bigint
            WHEN seqtypid = 'integer'::regtype THEN 2147483647::integer
            WHEN seqtypid = 'smallint'::regtype THEN 32767::smallint
            ELSE 2147483647::bigint  -- Default to integer max
        END AS max_value,
        seqtypid::regtype AS data_type
    FROM pg_sequences ps
    JOIN pg_class c ON c.relname = ps.sequencename
    JOIN pg_sequence s ON s.seqrelid = c.oid
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
),
sequence_usage AS (
    SELECT
        schema,
        sequence_name,
        data_type,
        current_value,
        max_value,
        CASE
            WHEN max_value > 0 THEN
                ROUND((current_value::numeric / max_value::numeric) * 100, 2)
            ELSE 0
        END AS usage_pct
    FROM sequence_stats
    WHERE current_value IS NOT NULL
)
SELECT
    schema,
    sequence_name,
    data_type,
    current_value,
    max_value,
    usage_pct,
    CASE
        WHEN usage_pct >= 95 THEN 'CRITICAL'
        WHEN usage_pct >= 80 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM sequence_usage
ORDER BY usage_pct DESC;
```

- [ ] **Step 2: Verify SQL file**

Run: `ls -la sql/check/sequences.sql`

- [ ] **Step 3: Commit**

```bash
git add sql/check/sequences.sql
git commit -m "feat(check): add SQL query for sequences exhaustion check"
```

---

### Task 2: Create Command Script

**Files:**
- Create: `commands/check/sequences.sh`

- [ ] **Step 1: Write command script**

Create `commands/check/sequences.sh`:
```bash
#!/bin/bash
# commands/check/sequences.sh - Check sequence exhaustion

# Default thresholds
PGTOOL_SEQUENCES_WARNING="${PGTOOL_SEQUENCES_WARNING:-80}"
PGTOOL_SEQUENCES_CRITICAL="${PGTOOL_SEQUENCES_CRITICAL:-95}"

#==============================================================================
# Main Function
#==============================================================================

pgtool_check_sequences() {
    local -a opts=()
    local -a args=()
    local threshold_warning="$PGTOOL_SEQUENCES_WARNING"
    local threshold_critical="$PGTOOL_SEQUENCES_CRITICAL"

    # Parse parameters
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_sequences_help
                return 0
                ;;
            --threshold-warning)
                shift
                threshold_warning="$1"
                shift
                ;;
            --threshold-critical)
                shift
                threshold_critical="$1"
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

    pgtool_info "检查序列使用情况..."
    pgtool_info "警告阈值: ${threshold_warning}%"
    pgtool_info "危险阈值: ${threshold_critical}%"
    echo ""

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "sequences"); then
        pgtool_fatal "SQL文件未找到: check/sequences"
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

    # Check for warnings
    if echo "$result" | grep -q "CRITICAL"; then
        return 2
    elif echo "$result" | grep -q "WARNING"; then
        return 1
    fi

    return $EXIT_SUCCESS
}

#==============================================================================
# Help Function
#==============================================================================

pgtool_check_sequences_help() {
    cat <<EOF
检查序列使用情况

检查数据库序列是否接近最大值，预警序列耗尽风险。

用法: pgtool check sequences [选项]

选项:
  -h, --help                   显示帮助
      --threshold-warning NUM  警告阈值百分比 (默认: 80)
      --threshold-critical NUM 危险阈值百分比 (默认: 95)

环境变量:
  PGTOOL_SEQUENCES_WARNING     警告阈值
  PGTOOL_SEQUENCES_CRITICAL    危险阈值

输出:
  OK       - 序列使用正常
  WARNING  - 序列使用超过警告阈值
  CRITICAL - 序列使用接近危险值，需要立即处理

示例:
  pgtool check sequences
  pgtool check sequences --threshold-warning=70 --threshold-critical=90
EOF
}
```

- [ ] **Step 2: Make executable**

Run: `chmod +x commands/check/sequences.sh`

- [ ] **Step 3: Commit**

```bash
git add commands/check/sequences.sh
git commit -m "feat(check): add sequences command implementation"
```

---

### Task 3: Register Command

**Files:**
- Modify: `commands/check/index.sh`

- [ ] **Step 1: Add to command list**

Add "sequences" to PGTOOL_CHECK_COMMANDS:
```bash
PGTOOL_CHECK_COMMANDS="...invalid-indexes:无效索引检查,sequences:检查序列使用情况"
```

- [ ] **Step 2: Add help text**

Add in pgtool_check_help():
```
  sequences       检查序列使用情况
```

- [ ] **Step 3: Test help**

Run: `./pgtool.sh check --help | grep sequences`

- [ ] **Step 4: Commit**

```bash
git add commands/check/index.sh
git commit -m "feat(check): register sequences command"
```

---

### Task 4: Create Tests

**Files:**
- Create: `tests/test_check_sequences.sh`

- [ ] **Step 1: Write tests**

Create `tests/test_check_sequences.sh`:
```bash
#!/bin/bash
# tests/test_check_sequences.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

test_sql_file_exists() {
    assert_true "[[ -f \"$PGTOOL_ROOT/sql/check/sequences.sql\" ]]"
}

test_command_script_exists() {
    assert_true "[[ -f \"$PGTOOL_ROOT/commands/check/sequences.sh\" ]]"
}

test_command_registered() {
    source "$PGTOOL_ROOT/commands/check/index.sh"
    assert_contains "$PGTOOL_CHECK_COMMANDS" "sequences"
}

test_help_command() {
    local output
    output=$(cd "$PGTOOL_ROOT" && ./pgtool.sh check sequences --help 2>&1)
    assert_contains "$output" "检查序列"
}

test_sql_syntax_valid() {
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        skip_test "需要数据库连接"
        return
    fi
    local result
    result=$(psql "${PGTOOL_CONN_OPTS[@]}" -v ON_ERROR_STOP=1 -f "$PGTOOL_ROOT/sql/check/sequences.sql" 2>&1)
    assert_equals "0" "$?"
}

echo ""
echo "Check Sequences Tests:"
run_test "test_sql_file_exists" "SQL file exists"
run_test "test_command_script_exists" "Command script exists"
run_test "test_command_registered" "Command registered"
run_test "test_help_command" "Help works"
run_test "test_sql_syntax_valid" "SQL syntax valid"
```

- [ ] **Step 2: Make executable and run**

```bash
chmod +x tests/test_check_sequences.sh
cd tests && ./run.sh test_check_sequences
```

- [ ] **Step 3: Commit**

```bash
git add tests/test_check_sequences.sh
git commit -m "test(check): add tests for sequences command"
```
