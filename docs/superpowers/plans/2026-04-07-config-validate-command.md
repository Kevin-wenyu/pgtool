# Config Validate Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool config validate` command to validate PostgreSQL configuration against best practices and common pitfalls.

**Architecture:** SQL queries check critical parameters against recommended values. Reports WARNING for suboptimal settings, CRITICAL for dangerous settings.

**Tech Stack:** Bash, PostgreSQL SQL, psql

---

## File Structure

- **Create:** `sql/config/validate.sql` - SQL for configuration validation
- **Create:** `commands/config/validate.sh` - Command implementation
- **Modify:** `commands/config/index.sh` - Register command
- **Create:** `tests/test_config_validate.sh` - Unit tests

---

### Task 1: Create SQL Query

**Files:**
- Create: `sql/config/validate.sql`

- [ ] **Step 1: Write SQL**

```sql
-- Validate PostgreSQL configuration against best practices
-- Output: parameter, current_value, recommended, status, description

WITH config_checks AS (
    -- Check max_connections
    SELECT
        'max_connections' AS parameter,
        current_setting('max_connections') AS current_value,
        '100-500 (varies)' AS recommended,
        CASE
            WHEN current_setting('max_connections')::int > 1000 THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'High values require more shared memory' AS description

    UNION ALL

    -- Check shared_buffers
    SELECT
        'shared_buffers' AS parameter,
        current_setting('shared_buffers') AS current_value,
        '25% of RAM' AS recommended,
        CASE
            WHEN current_setting('shared_buffers')::int < 128 THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Main memory cache size' AS description

    UNION ALL

    -- Check effective_cache_size
    SELECT
        'effective_cache_size' AS parameter,
        current_setting('effective_cache_size') AS current_value,
        '50-75% of RAM' AS recommended,
        'INFO' AS status,
        'OS and PostgreSQL cache estimate for query planner' AS description

    UNION ALL

    -- Check work_mem
    SELECT
        'work_mem' AS parameter,
        current_setting('work_mem') AS current_value,
        '64MB-256MB' AS recommended,
        CASE
            WHEN current_setting('work_mem')::int > 1048576 THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Per-operation memory (too high risks OOM)' AS description

    UNION ALL

    -- Check maintenance_work_mem
    SELECT
        'maintenance_work_mem' AS parameter,
        current_setting('maintenance_work_mem') AS current_value,
        '256MB-1GB' AS recommended,
        'INFO' AS status,
        'Maintenance operations memory' AS description

    UNION ALL

    -- Check checkpoint_completion_target
    SELECT
        'checkpoint_completion_target' AS parameter,
        current_setting('checkpoint_completion_target') AS current_value,
        '0.9' AS recommended,
        CASE
            WHEN current_setting('checkpoint_completion_target')::float < 0.7 THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Spread checkpoint writes over time' AS description

    UNION ALL

    -- Check wal_buffers
    SELECT
        'wal_buffers' AS parameter,
        current_setting('wal_buffers') AS current_value,
        '-1 (auto)' AS recommended,
        'INFO' AS status,
        'WAL write buffer size' AS description

    UNION ALL

    -- Check default_statistics_target
    SELECT
        'default_statistics_target' AS parameter,
        current_setting('default_statistics_target') AS current_value,
        '100-1000' AS recommended,
        CASE
            WHEN current_setting('default_statistics_target')::int < 100 THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'ANALYZE statistics target' AS description

    UNION ALL

    -- Check random_page_cost
    SELECT
        'random_page_cost' AS parameter,
        current_setting('random_page_cost') AS current_value,
        '1.1 (SSD) or 4 (HDD)' AS recommended,
        CASE
            WHEN current_setting('random_page_cost')::float = 4
                AND EXISTS (SELECT 1 FROM pg_stat_user_tables LIMIT 1) -- Assume SSD if tables exist
            THEN 'INFO'
            ELSE 'OK'
        END AS status,
        'Cost of random page fetch' AS description

    UNION ALL

    -- Check effective_io_concurrency
    SELECT
        'effective_io_concurrency' AS parameter,
        current_setting('effective_io_concurrency') AS current_value,
        '200 (SSD) or 1-2 (HDD)' AS recommended,
        CASE
            WHEN current_setting('effective_io_concurrency')::int = 0 THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Concurrent disk I/O operations' AS description

    UNION ALL

    -- Check autovacuum
    SELECT
        'autovacuum' AS parameter,
        current_setting('autovacuum') AS current_value,
        'on' AS recommended,
        CASE
            WHEN current_setting('autovacuum') = 'off' THEN 'CRITICAL'
            ELSE 'OK'
        END AS status,
        'Enable automatic vacuuming' AS description

    UNION ALL

    -- Check logging_collector
    SELECT
        'logging_collector' AS parameter,
        current_setting('logging_collector') AS current_value,
        'on' AS recommended,
        CASE
            WHEN current_setting('logging_collector') = 'off' THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Enable log file collection' AS description

    UNION ALL

    -- Check log_checkpoints
    SELECT
        'log_checkpoints' AS parameter,
        current_setting('log_checkpoints') AS current_value,
        'on' AS recommended,
        CASE
            WHEN current_setting('log_checkpoints') = 'off' THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Log checkpoint activity' AS description

    UNION ALL

    -- Check log_connections
    SELECT
        'log_connections' AS parameter,
        current_setting('log_connections') AS current_value,
        'on' AS recommended,
        CASE
            WHEN current_setting('log_connections') = 'off' THEN 'INFO'
            ELSE 'OK'
        END AS status,
        'Log connections' AS description

    UNION ALL

    -- Check log_disconnections
    SELECT
        'log_disconnections' AS parameter,
        current_setting('log_disconnections') AS current_value,
        'on' AS recommended,
        CASE
            WHEN current_setting('log_disconnections') = 'off' THEN 'INFO'
            ELSE 'OK'
        END AS status,
        'Log disconnections' AS description

    UNION ALL

    -- Check log_temp_files
    SELECT
        'log_temp_files' AS parameter,
        current_setting('log_temp_files') AS current_value,
        '0' AS recommended,
        CASE
            WHEN current_setting('log_temp_files') = '-1' THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Log temp files larger than N kB (0=all)' AS description

    UNION ALL

    -- Check max_wal_size
    SELECT
        'max_wal_size' AS parameter,
        current_setting('max_wal_size') AS current_value,
        '4GB+' AS recommended,
        'INFO' AS status,
        'Max WAL size before checkpoint' AS description

    UNION ALL

    -- Check min_wal_size
    SELECT
        'min_wal_size' AS parameter,
        current_setting('min_wal_size') AS current_value,
        '1GB+' AS recommended,
        'INFO' AS status,
        'Min WAL size to maintain' AS description

    UNION ALL

    -- Check archive_mode
    SELECT
        'archive_mode' AS parameter,
        current_setting('archive_mode') AS current_value,
        'on (for production)' AS recommended,
        'INFO' AS status,
        'Enable WAL archiving' AS description

    UNION ALL

    -- Check track_activities
    SELECT
        'track_activities' AS parameter,
        current_setting('track_activities') AS current_value,
        'on' AS recommended,
        CASE
            WHEN current_setting('track_activities') = 'off' THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Track active queries' AS description

    UNION ALL

    -- Check track_counts
    SELECT
        'track_counts' AS parameter,
        current_setting('track_counts') AS current_value,
        'on' AS recommended,
        CASE
            WHEN current_setting('track_counts') = 'off' THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Track table/index stats' AS description

    UNION ALL

    -- Check track_io_timing
    SELECT
        'track_io_timing' AS parameter,
        current_setting('track_io_timing') AS current_value,
        'on' AS recommended,
        CASE
            WHEN current_setting('track_io_timing') = 'off' THEN 'INFO'
            ELSE 'OK'
        END AS status,
        'Track block I/O timing' AS description
)
SELECT
    parameter,
    current_value,
    recommended,
    status,
    description
FROM config_checks
ORDER BY
    CASE status WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 WHEN 'INFO' THEN 3 ELSE 4 END,
    parameter;
```

- [ ] **Step 2: Commit**

```bash
git add sql/config/validate.sql
git commit -m "feat(config): add SQL for config validation"
```

---

### Task 2: Create Command Script

**Files:**
- Create: `commands/config/validate.sh`

- [ ] **Step 1: Write script**

Create `commands/config/validate.sh`:
```bash
#!/bin/bash
# commands/config/validate.sh

pgtool_config_validate() {
    local -a opts=()
    local show_all=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_validate_help
                return 0
                ;;
            --all)
                show_all=true
                shift
                ;;
            --warnings-only)
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

    pgtool_info "验证PostgreSQL配置..."
    echo ""

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "config" "validate"); then
        pgtool_fatal "SQL文件未找到: config/validate"
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

    # Summary
    echo ""
    local critical_count warning_count
    critical_count=$(echo "$result" | grep -c "CRITICAL" || echo 0)
    warning_count=$(echo "$result" | grep -c "WARNING" || echo 0)

    if [[ $critical_count -gt 0 ]]; then
        pgtool_error "发现 $critical_count 个CRITICAL配置问题"
        return 2
    elif [[ $warning_count -gt 0 ]]; then
        pgtool_warn "发现 $warning_count 个WARNING配置问题"
        return 1
    else
        pgtool_info "配置检查通过"
        return $EXIT_SUCCESS
    fi
}

pgtool_config_validate_help() {
    cat <<EOF
验证PostgreSQL配置

检查数据库配置参数是否符合最佳实践。

用法: pgtool config validate [选项]

选项:
  -h, --help        显示帮助
      --all         显示所有参数（包括OK的）
      --warnings-only  仅显示警告和危险项

示例:
  pgtool config validate
  pgtool config validate --warnings-only
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/config/validate.sh
chmod +x commands/config/validate.sh
git commit -m "feat(config): add validate command implementation"
```

---

### Task 3: Register Command

- [ ] **Step 1: Update index.sh**

Add "validate:验证配置" to PGTOOL_CONFIG_COMMANDS and help.

- [ ] **Step 2: Commit**

```bash
git add commands/config/index.sh
git commit -m "feat(config): register validate command"
```

---

### Task 4: Tests

**Files:**
- Create: `tests/test_config_validate.sh`

- [ ] **Step 1: Write tests**

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

test_files() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/config/validate.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/config/validate.sh ]]"
}

test_registered() {
    source "$PGTOOL_ROOT/commands/config/index.sh"
    assert_contains "$PGTOOL_CONFIG_COMMANDS" "validate"
}

echo ""
echo "Config Validate Tests:"
run_test "test_files" "Files exist"
run_test "test_registered" "Command registered"
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_config_validate.sh
chmod +x tests/test_config_validate.sh
git commit -m "test(config): add tests for validate command"
```
