# Admin Rotate-Log Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool admin rotate-log` command to trigger PostgreSQL log rotation.

**Architecture:** Execute pg_rotate_logfile() function. Requires appropriate permissions. Similar to admin/checkpoint pattern.

**Tech Stack:** Bash, PostgreSQL SQL

---

## File Structure

- **Create:** `sql/admin/rotate_log.sql`
- **Create:** `commands/admin/rotate_log.sh`
- **Modify:** `commands/admin/index.sh`
- **Create:** `tests/test_admin_rotate_log.sh`

---

### Task 1: Create SQL

**Files:**
- Create: `sql/admin/rotate_log.sql`

- [ ] **Step 1: Write SQL**

```sql
-- Rotate PostgreSQL log file
-- Returns: status message

DO $$
DECLARE
    result text;
BEGIN
    -- Check if log rotation is supported
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'pg_rotate_logfile') THEN
        result := pg_rotate_logfile();
        IF result THEN
            RAISE NOTICE 'Log file rotated successfully';
        ELSE
            RAISE NOTICE 'Log rotation not needed or not configured';
        END IF;
    ELSE
        RAISE EXCEPTION 'pg_rotate_logfile not available - log rotation requires logging_collector to be enabled';
    END IF;
END $$;

-- Return confirmation
SELECT 'Log rotation completed' AS status;
```

- [ ] **Step 2: Commit**

```bash
git add sql/admin/rotate_log.sql
git commit -m "feat(admin): add SQL for rotate-log command"
```

---

### Task 2: Create Command

**Files:**
- Create: `commands/admin/rotate_log.sh`

- [ ] **Step 1: Write script**

```bash
#!/bin/bash
# commands/admin/rotate_log.sh

pgtool_admin_rotate_log() {
    local -a opts=()
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_admin_rotate_log_help
                return 0
                ;;
            --force)
                force=true
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

    if [[ "$force" != "true" ]]; then
        pgtool_error "此操作将轮换PostgreSQL日志文件"
        pgtool_error "请使用 --force 确认执行"
        return $EXIT_INVALID_ARGS
    fi

    pgtool_info "轮换日志文件..."
    echo ""

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "admin" "rotate_log"); then
        pgtool_fatal "SQL文件未找到: admin/rotate_log"
    fi

    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    pgtool_info "日志轮换完成"
    echo "$result"
    return $EXIT_SUCCESS
}

pgtool_admin_rotate_log_help() {
    cat <<EOF
轮换PostgreSQL日志文件

触发PostgreSQL立即轮换当前日志文件。
需要 logging_collector 已启用。

用法: pgtool admin rotate-log [选项]

选项:
  -h, --help    显示帮助
      --force   确认执行操作

警告:
  此操作需要适当的数据库权限。

示例:
  pgtool admin rotate-log --force
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/admin/rotate_log.sh
chmod +x commands/admin/rotate_log.sh
git commit -m "feat(admin): add rotate-log command implementation"
```

---

### Task 3: Register

- [ ] **Step 1: Update index.sh**

Add "rotate-log:轮换日志文件" to PGTOOL_ADMIN_COMMANDS.

- [ ] **Step 2: Commit**

```bash
git add commands/admin/index.sh
git commit -m "feat(admin): register rotate-log command"
```

---

### Task 4: Tests

**Files:**
- Create: `tests/test_admin_rotate_log.sh`

- [ ] **Step 1: Write tests**

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

test_files() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/admin/rotate_log.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/admin/rotate_log.sh ]]"
}

test_registered() {
    source "$PGTOOL_ROOT/commands/admin/index.sh"
    assert_contains "$PGTOOL_ADMIN_COMMANDS" "rotate-log"
}

test_requires_force() {
    local output
    output=$(cd "$PGTOOL_ROOT" && ./pgtool.sh admin rotate-log 2>&1)
    assert_contains "$output" "--force"
}

echo ""
echo "Admin Rotate-Log Tests:"
run_test "test_files" "Files exist"
run_test "test_registered" "Command registered"
run_test "test_requires_force" "Requires force flag"
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_admin_rotate_log.sh
chmod +x tests/test_admin_rotate_log.sh
git commit -m "test(admin): add tests for rotate-log command"
```
