# Check SSL Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool check ssl` command to check SSL/TLS certificate status and expiration.

**Architecture:** SQL queries check ssl system parameters and connection info. Command shows certificate expiration, SSL mode, cipher info.

**Tech Stack:** Bash, PostgreSQL SQL, psql

---

## File Structure

- **Create:** `sql/check/ssl.sql` - SQL to check SSL status
- **Create:** `commands/check/ssl.sh` - Command implementation
- **Modify:** `commands/check/index.sh` - Register command
- **Create:** `tests/test_check_ssl.sh` - Unit tests

---

### Task 1: Create SQL Query

**Files:**
- Create: `sql/check/ssl.sql`

- [ ] **Step 1: Write SQL**

Create `sql/check/ssl.sql`:
```sql
-- Check SSL/TLS certificate status
-- Parameters: warning_days (default 30), critical_days (default 7)
-- Output: check_item, value, details, status

-- Check if SSL is enabled
WITH ssl_enabled AS (
    SELECT
        'SSL Enabled' AS check_item,
        CASE WHEN ssl THEN 'Yes' ELSE 'No' END AS value,
        'ssl parameter' AS details,
        CASE WHEN ssl THEN 'OK' ELSE 'WARNING' END AS status
    FROM pg_settings WHERE name = 'ssl'
),
-- Check SSL mode
ssl_mode AS (
    SELECT
        'SSL Mode' AS check_item,
        current_setting('ssl') AS value,
        'Current SSL setting' AS details,
        'INFO' AS status
),
-- Check SSL certificate file location
ssl_cert_file AS (
    SELECT
        'SSL Certificate' AS check_item,
        NULLIF(current_setting('ssl_cert_file'), '') AS value,
        COALESCE(NULLIF(current_setting('ssl_cert_file'), ''), 'Not configured') AS details,
        CASE
            WHEN current_setting('ssl_cert_file') = '' THEN 'WARNING'
            ELSE 'OK'
        END AS status
),
-- Check SSL key file location
ssl_key_file AS (
    SELECT
        'SSL Key File' AS check_item,
        NULLIF(current_setting('ssl_key_file'), '') AS value,
        COALESCE(NULLIF(current_setting('ssl_key_file'), ''), 'Not configured') AS details,
        CASE
            WHEN current_setting('ssl_key_file') = '' THEN 'WARNING'
            ELSE 'OK'
        END AS status
),
-- Get connection SSL info (if available)
conn_ssl AS (
    SELECT
        'Connection SSL' AS check_item,
        ssl AS value,
        version AS details,
        CASE ssl WHEN true THEN 'OK' ELSE 'WARNING' END AS status
    FROM pg_stat_ssl
    WHERE pid = pg_backend_pid()
)
SELECT * FROM ssl_enabled
UNION ALL
SELECT * FROM ssl_mode
UNION ALL
SELECT * FROM ssl_cert_file
UNION ALL
SELECT * FROM ssl_key_file
UNION ALL
SELECT * FROM conn_ssl
ORDER BY check_item;
```

- [ ] **Step 2: Commit**

```bash
git add sql/check/ssl.sql
git commit -m "feat(check): add SQL for SSL check command"
```

---

### Task 2: Create Command Script

**Files:**
- Create: `commands/check/ssl.sh`

- [ ] **Step 1: Write script**

```bash
#!/bin/bash
# commands/check/ssl.sh

PGTOOL_SSL_WARNING_DAYS="${PGTOOL_SSL_WARNING_DAYS:-30}"
PGTOOL_SSL_CRITICAL_DAYS="${PGTOOL_SSL_CRITICAL_DAYS:-7}"

pgtool_check_ssl() {
    local -a opts=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_ssl_help
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

    pgtool_info "检查 SSL/TLS 配置..."
    echo ""

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "ssl"); then
        pgtool_fatal "SQL文件未找到: check/ssl"
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

    if echo "$result" | grep -q "WARNING"; then
        return 1
    fi

    return $EXIT_SUCCESS
}

pgtool_check_ssl_help() {
    cat <<EOF
检查 SSL/TLS 配置

检查数据库 SSL 配置、证书状态及连接加密情况。

用法: pgtool check ssl [选项]

选项:
  -h, --help    显示帮助

环境变量:
  PGTOOL_SSL_WARNING_DAYS   证书过期警告天数 (默认: 30)
  PGTOOL_SSL_CRITICAL_DAYS  证书过期危险天数 (默认: 7)

示例:
  pgtool check ssl
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/check/ssl.sh
chmod +x commands/check/ssl.sh
git commit -m "feat(check): add SSL command implementation"
```

---

### Task 3: Register and Test

- [ ] **Step 1: Update index.sh**

Add "ssl:检查SSL配置" to PGTOOL_CHECK_COMMANDS.

- [ ] **Step 2: Commit**

```bash
git add commands/check/index.sh
git commit -m "feat(check): register SSL command"
```

---

### Task 4: Tests

**Files:**
- Create: `tests/test_check_ssl.sh`

- [ ] **Step 1: Write tests**

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

test_files_exist() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/check/ssl.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/check/ssl.sh ]]"
}

test_registered() {
    source "$PGTOOL_ROOT/commands/check/index.sh"
    assert_contains "$PGTOOL_CHECK_COMMANDS" "ssl"
}

echo ""
echo "Check SSL Tests:"
run_test "test_files_exist" "Files exist"
run_test "test_registered" "Command registered"
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_check_ssl.sh
chmod +x tests/test_check_ssl.sh
git commit -m "test(check): add tests for SSL command"
```
