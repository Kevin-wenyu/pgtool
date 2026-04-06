# Extend Check Command Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing `check` command group with ready, deadlocks, and invalid-indexes commands for additional health checks.

**Architecture:** Uses existing check infrastructure - commands/check/*.sh for command implementations, sql/check/*.sql for SQL templates. No new library needed (uses existing lib/check.sh).

**Tech Stack:** Bash, PostgreSQL SQL, psql CLI

---

## Files to Create

- `commands/check/ready.sh` - Database readiness check command
- `commands/check/deadlocks.sh` - Deadlock detection command
- `commands/check/invalid_indexes.sh` - Invalid index detection command
- `sql/check/ready.sql` - Ready check SQL template
- `sql/check/deadlocks.sql` - Deadlocks SQL template
- `sql/check/invalid_indexes.sql` - Invalid indexes SQL template

## Files to Modify

- `commands/check/index.sh` - Add new commands to PGTOOL_CHECK_COMMANDS

---

### Task 1: Create Ready Check Command

**Files:**
- Create: `commands/check/ready.sh`
- Create: `sql/check/ready.sql`

- [ ] **Step 1: Write the SQL template**

File: `sql/check/ready.sql`
```sql
-- sql/check/ready.sql
-- 检查数据库是否就绪（可接受连接）

WITH readiness_check AS (
    SELECT 
        pg_is_in_recovery() as in_recovery,
        pg_current_wal_lsn() as current_lsn,
        current_setting('max_connections') as max_conn,
        (SELECT count(*) FROM pg_stat_activity) as current_conn
)
SELECT 
    CASE 
        WHEN in_recovery AND :accept_standby = 0 THEN 'STANDBY'
        ELSE 'READY'
    END as status,
    CASE 
        WHEN in_recovery THEN '数据库处于恢复模式（备库）'
        ELSE '数据库正常运行'
    END as description,
    max_conn as max_connections,
    current_conn as current_connections,
    round(current_conn::numeric / max_conn::numeric * 100, 2) as connection_usage_pct
FROM readiness_check;
```

- [ ] **Step 2: Write the command script**

File: `commands/check/ready.sh`
```bash
#!/bin/bash
# commands/check/ready.sh - 检查数据库就绪状态

# 默认是否接受备库
PGTOOL_CHECK_READY_ACCEPT_STANDBY="${PGTOOL_CHECK_READY_ACCEPT_STANDBY:-0}"

pgtool_check_ready() {
    local -a opts=()
    local accept_standby="$PGTOOL_CHECK_READY_ACCEPT_STANDBY"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_ready_help
                return 0
                ;;
            --accept-standby)
                accept_standby=1
                shift
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
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

    pgtool_info "检查数据库就绪状态..."
    echo ""

    # 测试连接（静默）
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        pgtool_error "数据库连接失败 - 未就绪"
        return $EXIT_CONNECTION_ERROR
    fi

    # 查找SQL文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "ready"); then
        pgtool_fatal "SQL文件未找到: check/ready"
    fi

    # 替换参数
    local sql_content
    sql_content=$(sed "s/:accept_standby/${accept_standby}/g" "$sql_file")

    # 执行SQL
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(echo "$sql_content" | timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # 检查状态
    local status
    status=$(echo "$result" | grep -E "^\\s*(READY|STANDBY|NOT_READY)" | head -1 | tr -d ' ')

    if [[ "$status" == "READY" ]]; then
        pgtool_info "数据库就绪 - 正常运行"
        return $EXIT_SUCCESS
    elif [[ "$status" == "STANDBY" ]]; then
        pgtool_warn "数据库处于恢复模式（备库）"
        return 1
    else
        pgtool_error "数据库状态异常"
        return $EXIT_SQL_ERROR
    fi
}

pgtool_check_ready_help() {
    cat << 'EOF'
检查数据库是否就绪

检查数据库是否可接受连接并正常运行。

用法: pgtool check ready [选项]

选项:
  -h, --help           显示帮助
      --accept-standby 接受备库为就绪状态

返回值:
  0 - 数据库就绪（正常运行）
  1 - 数据库是备库（仅当未使用--accept-standby）
  3 - 连接失败

示例:
  pgtool check ready
  pgtool check ready --accept-standby

用途:
  - 健康检查端点（如Kubernetes livenessProbe）
  - 部署前验证数据库状态
  - CI/CD管道中确认数据库可用
EOF
}
```

- [ ] **Step 3: Make file executable and commit**

```bash
chmod +x commands/check/ready.sh
git add commands/check/ready.sh sql/check/ready.sql
git commit -m "feat(check): add ready command for database readiness check"
```

---

### Task 2: Create Deadlocks Check Command

**Files:**
- Create: `commands/check/deadlocks.sh`
- Create: `sql/check/deadlocks.sql`

- [ ] **Step 1: Write the SQL template**

File: `sql/check/deadlocks.sql`
```sql
-- sql/check/deadlocks.sql
-- 检查死锁

-- 获取死锁统计
SELECT 
    datname as database,
    deadlocks,
    stats_reset,
    CASE 
        WHEN deadlocks > :threshold THEN 'WARNING'
        ELSE 'OK'
    END as status,
    CASE 
        WHEN deadlocks > 0 THEN '自上次统计重置以来发生' || deadlocks || '次死锁'
        ELSE '未检测到死锁'
    END as description
FROM pg_stat_database
WHERE datname = current_database()
ORDER BY deadlocks DESC;
```

- [ ] **Step 2: Write the command script**

File: `commands/check/deadlocks.sh`
```bash
#!/bin/bash
# commands/check/deadlocks.sh - 检查死锁

PGTOOL_CHECK_DEADLOCKS_THRESHOLD="${PGTOOL_CHECK_DEADLOCKS_THRESHOLD:-1}"

pgtool_check_deadlocks() {
    local -a opts=()
    local threshold="$PGTOOL_CHECK_DEADLOCKS_THRESHOLD"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_deadlocks_help
                return 0
                ;;
            --threshold)
                shift
                threshold="$1"
                shift
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
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

    pgtool_info "检查死锁统计..."
    pgtool_info "阈值: ${threshold} 次死锁"
    echo ""

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "deadlocks"); then
        pgtool_fatal "SQL文件未找到: check/deadlocks"
    fi

    local sql_content
    sql_content=$(sed "s/:threshold/${threshold}/g" "$sql_file")

    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(echo "$sql_content" | timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # 检查结果
    local warning_count
    warning_count=$(echo "$result" | grep -c "WARNING" || echo "0")

    if [[ $warning_count -gt 0 ]]; then
        pgtool_warn "检测到死锁活动！"
        return 1
    fi

    pgtool_info "未检测到死锁问题"
    return $EXIT_SUCCESS
}

pgtool_check_deadlocks_help() {
    cat << 'EOF'
检查数据库死锁情况

用法: pgtool check deadlocks [选项]

选项:
  -h, --help           显示帮助
      --threshold NUM  死锁警告阈值（默认: 1）

说明:
  检查自统计重置以来发生的死锁次数。
  死锁是事务相互等待导致的循环依赖，
  PostgreSQL会自动回滚其中一个事务，但频繁死锁影响性能。

返回值:
  0 - 死锁数在阈值范围内
  1 - 死锁数超过阈值

示例:
  pgtool check deadlocks
  pgtool check deadlocks --threshold=5

注意:
  统计在stats_reset后重置。查看统计重置时间：
  SELECT stats_reset FROM pg_stat_database WHERE datname = current_database();
EOF
}
```

- [ ] **Step 3: Make file executable and commit**

```bash
chmod +x commands/check/deadlocks.sh
git add commands/check/deadlocks.sh sql/check/deadlocks.sql
git commit -m "feat(check): add deadlocks command for deadlock detection"
```

---

### Task 3: Create Invalid Indexes Check Command

**Files:**
- Create: `commands/check/invalid_indexes.sh`
- Create: `sql/check/invalid_indexes.sql`

- [ ] **Step 1: Write the SQL template**

File: `sql/check/invalid_indexes.sql`
```sql
-- sql/check/invalid_indexes.sql
-- 检查无效索引

SELECT 
    schemaname || '.' || indexrelname as index_name,
    schemaname || '.' || relname as table_name,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    'INVALID' as status,
    '索引已失效，需要重建' as recommendation
FROM pg_stat_user_indexes sui
JOIN pg_index pi ON sui.indexrelid = pi.indexrelid
WHERE NOT pi.indisvalid
ORDER BY pg_relation_size(indexrelid) DESC;
```

- [ ] **Step 2: Write the command script**

File: `commands/check/invalid_indexes.sh`
```bash
#!/bin/bash
# commands/check/invalid_indexes.sh - 检查无效索引

pgtool_check_invalid_indexes() {
    local -a opts=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_invalid_indexes_help
                return 0
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
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

    pgtool_info "检查无效索引..."
    echo ""

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "invalid_indexes"); then
        pgtool_fatal "SQL文件未找到: check/invalid_indexes"
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
        pgtool_error "SQL执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # 检查是否有无效索引
    local count
    count=$(echo "$result" | grep -c "INVALID" || echo "0")
    count=$(echo "$count" | tr -d '\n')

    if [[ $count -gt 0 ]]; then
        pgtool_warn "发现 ${count} 个无效索引"
        pgtool_info "使用 'pgtool maintenance reindex --index=<name>' 重建索引"
        return 1
    fi

    pgtool_info "未发现无效索引"
    return $EXIT_SUCCESS
}

pgtool_check_invalid_indexes_help() {
    cat << 'EOF'
检查无效索引

查找因失败操作（如失败的CREATE INDEX CONCURRENTLY）导致的无效索引。
无效索引占用空间但不参与查询优化。

用法: pgtool check invalid-indexes [选项]

选项:
  -h, --help       显示帮助

说明:
  无效索引通常在以下情况产生:
  - CREATE INDEX CONCURRENTLY被中断
  - REINDEX CONCURRENTLY失败
  - 其他索引操作异常终止

返回值:
  0 - 无无效索引
  1 - 发现无效索引

示例:
  pgtool check invalid-indexes

修复:
  pgtool maintenance reindex --index=idx_name
EOF
}
```

- [ ] **Step 3: Make file executable and commit**

```bash
chmod +x commands/check/invalid_indexes.sh
git add commands/check/invalid_indexes.sh sql/check/invalid_indexes.sql
git commit -m "feat(check): add invalid-indexes command"
```

---

### Task 4: Update Check Group Index

**Files:**
- Modify: `commands/check/index.sh`

- [ ] **Step 1: Read current index file**

Run: `cat commands/check/index.sh`

- [ ] **Step 2: Update PGTOOL_CHECK_COMMANDS variable**

Add the new commands to the list:

Change from:
```bash
PGTOOL_CHECK_COMMANDS="xid:XID年龄检查,replication:复制状态检查,autovacuum:自动清理检查,connection:连接数检查"
```

To:
```bash
PGTOOL_CHECK_COMMANDS="xid:XID年龄检查,replication:复制状态检查,autovacuum:自动清理检查,connection:连接数检查,cache-hit:缓存命中率检查,long-tx:长事务检查,replication-lag:复制延迟检查,tablespace:表空间检查,ready:就绪状态检查,deadlocks:死锁检查,invalid-indexes:无效索引检查"
```

- [ ] **Step 3: Update help text**

Add the new commands to the help output after "可用命令:" section:

```
  cache-hit     检查缓存命中率
  long-tx       检查长事务
  replication-lag 检查复制延迟
  tablespace    检查表空间使用率
  ready         检查数据库就绪状态
  deadlocks     检查死锁情况
  invalid-indexes 检查无效索引
```

- [ ] **Step 4: Commit**

```bash
git add commands/check/index.sh
git commit -m "feat(check): register new check commands in index"
```

---

### Task 5: Create Tests

**Files:**
- Modify: `tests/test_commands.sh` (add tests for new commands)

- [ ] **Step 1: Add tests for new check commands**

Add to `tests/test_commands.sh`:

```bash
# Test new check commands exist
test_check_ready_command_exists() {
    assert_true "$(test -f \"$PGTOOL_ROOT/commands/check/ready.sh\" && echo 0 || echo 1)" "ready.sh should exist"
}

test_check_deadlocks_command_exists() {
    assert_true "$(test -f \"$PGTOOL_ROOT/commands/check/deadlocks.sh\" && echo 0 || echo 1)" "deadlocks.sh should exist"
}

test_check_invalid_indexes_command_exists() {
    assert_true "$(test -f \"$PGTOOL_ROOT/commands/check/invalid_indexes.sh\" && echo 0 || echo 1)" "invalid_indexes.sh should exist"
}

test_check_ready_sql_exists() {
    assert_true "$(test -f \"$PGTOOL_ROOT/sql/check/ready.sql\" && echo 0 || echo 1)" "ready.sql should exist"
}

test_check_deadlocks_sql_exists() {
    assert_true "$(test -f \"$PGTOOL_ROOT/sql/check/deadlocks.sql\" && echo 0 || echo 1)" "deadlocks.sql should exist"
}

test_check_invalid_indexes_sql_exists() {
    assert_true "$(test -f \"$PGTOOL_ROOT/sql/check/invalid_indexes.sql\" && echo 0 || echo 1)" "invalid_indexes.sql should exist"
}
```

Add run_test calls at the end:
```bash
run_test "test_check_ready_command_exists"
run_test "test_check_deadlocks_command_exists"
run_test "test_check_invalid_indexes_command_exists"
run_test "test_check_ready_sql_exists"
run_test "test_check_deadlocks_sql_exists"
run_test "test_check_invalid_indexes_sql_exists"
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_commands.sh
git commit -m "test(check): add tests for new check commands"
```

---

## Verification Checklist

After all tasks complete, verify:

- [ ] `./pgtool.sh check --help` shows new commands
- [ ] `./pgtool.sh check ready --help` works
- [ ] `./pgtool.sh check deadlocks --help` works
- [ ] `./pgtool.sh check invalid-indexes --help` works
- [ ] `cd tests && ./run.sh test_commands` passes all tests
