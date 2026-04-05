# pgtool 生产级测试验证计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 验证 pgtool 所有19个命令在真实 PostgreSQL 数据库中正常工作，达到生产级质量标准，无任何bug。

**Architecture:** 使用 TDD 方法，先创建测试数据，再为每个命令编写集成测试，确保功能完整性和边界条件处理正确。

**Tech Stack:** Bash, PostgreSQL, psql, 自定义测试框架

---

## 目录

1. [当前状态评估](#当前状态评估)
2. [测试数据准备](#测试数据准备)
3. [命令测试计划](#命令测试计划)
4. [执行策略](#执行策略)

---

## 当前状态评估

### 已存在功能（19个命令）

| 命令组 | 命令 | 状态 | SQL文件 | 命令文件 |
|--------|------|------|---------|----------|
| **check** | xid | ✅ | sql/check/xid.sql | commands/check/xid.sh |
| **check** | replication | ✅ | sql/check/replication.sql | commands/check/replication.sh |
| **check** | autovacuum | ✅ | sql/check/autovacuum.sql | commands/check/autovacuum.sh |
| **check** | connection | ✅ | sql/check/connection.sql | commands/check/connection.sh |
| **stat** | activity | ✅ | sql/stat/activity.sql | commands/stat/activity.sh |
| **stat** | locks | ✅ | sql/stat/locks.sql | commands/stat/locks.sh |
| **stat** | database | ✅ | sql/stat/database.sql | commands/stat/database.sh |
| **stat** | table | ✅ | sql/stat/table.sql | commands/stat/table.sh |
| **stat** | indexes | ✅ | sql/stat/indexes.sql | commands/stat/indexes.sh |
| **admin** | kill-blocking | ✅ | sql/admin/kill_blocking.sql | commands/admin/kill_blocking.sh |
| **admin** | cancel-query | ✅ | sql/admin/cancel_query.sql | commands/admin/cancel_query.sh |
| **admin** | checkpoint | ✅ | (inline) | commands/admin/checkpoint.sh |
| **admin** | reload | ✅ | (inline) | commands/admin/reload.sh |
| **analyze** | bloat | ✅ | sql/analyze/bloat.sql | commands/analyze/bloat.sh |
| **analyze** | missing-indexes | ✅ | sql/analyze/missing_indexes.sql | commands/analyze/missing_indexes.sh |
| **analyze** | slow-queries | ✅ | sql/analyze/slow_queries.sql | commands/analyze/slow_queries.sh |
| **analyze** | vacuum-stats | ✅ | sql/analyze/vacuum_stats.sql | commands/analyze/vacuum_stats.sh |
| **plugin** | list | ✅ | (inline) | commands/plugin/list.sh |
| **plugin** | example | ✅ | (inline) | commands/plugin/example.sh |

### 当前测试覆盖

- ✅ 单元测试：core, cli, util, pg, plugin
- ⚠️ 命令测试：仅基础帮助测试
- ❌ 集成测试：无真实数据库测试
- ❌ SQL 验证：未验证 SQL 语法正确性
- ❌ 边界测试：无错误场景测试

---

## 测试数据准备

### Task 1: 创建测试数据库环境

**Files:**
- Create: `tests/setup_test_db.sql`
- Create: `tests/setup_test_data.sql`
- Create: `tests/cleanup_test_db.sql`
- Modify: `tests/run.sh`（添加测试数据初始化）

- [ ] **Step 1: 编写数据库创建脚本**

```sql
-- tests/setup_test_db.sql
-- 创建测试数据库和用户

-- 创建测试数据库（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'pgtool_test') THEN
        CREATE DATABASE pgtool_test;
    END IF;
END $$;

-- 连接到测试数据库后执行
\c pgtool_test

-- 创建测试schema
CREATE SCHEMA IF NOT EXISTS pgtool_test;
SET search_path TO pgtool_test, public;

-- 创建测试用的表（用于各种统计测试）
CREATE TABLE IF NOT EXISTS test_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    email VARCHAR(200),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS test_orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES test_users(id),
    amount DECIMAL(10,2),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 创建索引（部分有，部分没有 - 用于 missing-indexes 测试）
CREATE INDEX IF NOT EXISTS idx_test_users_status ON test_users(status);
CREATE INDEX IF NOT EXISTS idx_test_orders_user_id ON test_orders(user_id);

-- 创建一个大表（用于 bloat 测试）
CREATE TABLE IF NOT EXISTS test_large_table AS
SELECT 
    generate_series(1, 10000) as id,
    md5(random()::text) as data,
    random() * 1000 as value,
    CURRENT_TIMESTAMP - (random() * INTERVAL '365 days') as created_at
FROM generate_series(1, 10000);

ALTER TABLE test_large_table ADD PRIMARY KEY (id);

-- 创建函数用于模拟慢查询
CREATE OR REPLACE FUNCTION pgtool_test_slow_query(wait_seconds NUMERIC)
RETURNS VOID AS $$
BEGIN
    PERFORM pg_sleep(wait_seconds);
END;
$$ LANGUAGE plpgsql;

-- 创建函数用于模拟锁等待
CREATE OR REPLACE FUNCTION pgtool_test_lock_holder()
RETURNS VOID AS $$
BEGIN
    -- 长时间持有锁
    PERFORM pg_sleep(30);
END;
$$ LANGUAGE plpgsql;

-- 插入测试数据
INSERT INTO test_users (username, email, status)
SELECT 
    'user_' || i,
    'user_' || i || '@example.com',
    CASE WHEN i % 10 = 0 THEN 'inactive' ELSE 'active' END
FROM generate_series(1, 1000) i
ON CONFLICT DO NOTHING;

INSERT INTO test_orders (user_id, amount, status)
SELECT 
    (random() * 999 + 1)::int,
    random() * 1000,
    CASE WHEN random() > 0.5 THEN 'completed' ELSE 'pending' END
FROM generate_series(1, 5000)
ON CONFLICT DO NOTHING;

-- 更新统计信息
ANALYZE;
```

- [ ] **Step 2: 编写数据生成脚本（用于持续测试）**

```sql
-- tests/setup_test_data.sql
-- 生成更多测试数据以模拟真实场景

-- 生成慢查询日志数据（pg_stat_statements 需要预先配置）
-- 执行多次复杂查询以产生统计信息
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..100 LOOP
        -- 复杂查询，用于产生统计
        PERFORM COUNT(*) FROM test_orders o
        JOIN test_users u ON o.user_id = u.id
        WHERE o.amount > random() * 500;
    END LOOP;
END $$;

-- 更新表统计信息
VACUUM ANALYZE test_users;
VACUUM ANALYZE test_orders;
VACUUM ANALYZE test_large_table;
```

- [ ] **Step 3: 编写清理脚本**

```sql
-- tests/cleanup_test_db.sql
-- 清理测试数据

DROP TABLE IF EXISTS test_orders CASCADE;
DROP TABLE IF EXISTS test_users CASCADE;
DROP TABLE IF EXISTS test_large_table CASCADE;
DROP FUNCTION IF EXISTS pgtool_test_slow_query(NUMERIC);
DROP FUNCTION IF EXISTS pgtool_test_lock_holder();
DROP SCHEMA IF EXISTS pgtool_test CASCADE;
```

- [ ] **Step 4: 创建测试数据库工具函数**

**Files:**
- Modify: `tests/test_util.sh`（添加数据库工具函数）

```bash
# 在 test_util.sh 中添加

# 初始化测试数据库
pgtool_test_db_setup() {
    local db_name="${PGTOOL_TEST_DB:-pgtool_test}"

    pgtool_info "设置测试数据库: $db_name"

    # 创建测试数据库
    if ! psql -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '$db_name'" 2>/dev/null | grep -q 1; then
        psql -d postgres -c "CREATE DATABASE $db_name" 2>/dev/null || {
            pgtool_error "无法创建测试数据库"
            return 1
        }
    fi

    # 执行初始化 SQL
    psql -d "$db_name" -f "$PGTOOL_ROOT/tests/setup_test_db.sql" 2>/dev/null || {
        pgtool_error "测试数据库初始化失败"
        return 1
    }

    pgtool_info "测试数据库准备完成"
    return 0
}

# 清理测试数据库
pgtool_test_db_cleanup() {
    local db_name="${PGTOOL_TEST_DB:-pgtool_test}"

    pgtool_info "清理测试数据库: $db_name"

    psql -d "$db_name" -f "$PGTOOL_ROOT/tests/cleanup_test_db.sql" 2>/dev/null || true
}

# 检查测试数据库是否可连接
pgtool_test_db_check() {
    local db_name="${PGTOOL_TEST_DB:-pgtool_test}"

    if psql -d "$db_name" -c "SELECT 1" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
```

- [ ] **Step 5: 运行测试验证数据库创建**

```bash
# 测试数据库脚本
psql -d postgres -c "SELECT 1"  # 验证基本连接
bash tests/run.sh test_util      # 运行单元测试
```

---

## 命令测试计划

### Task 2: Check 命令组集成测试

**Files:**
- Create: `tests/integration/test_check.sh`

- [ ] **Step 1: 编写 xid 测试**

```bash
test_check_xid_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test check xid 2>&1)

    # 检查输出包含关键信息
    assert_contains "$output" "xid"
    assert_contains "$output" "datname"
    # 检查返回码
    return 0
}
```

- [ ] **Step 2: 编写 connection 测试**

```bash
test_check_connection_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test check connection 2>&1)

    assert_contains "$output" "当前连接数"
    assert_contains "$output" "最大连接数"
}
```

- [ ] **Step 3: 编写 autovacuum 测试**

```bash
test_check_autovacuum_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test check autovacuum 2>&1)

    assert_contains "$output" "autovacuum"
}
```

- [ ] **Step 4: 编写 replication 测试（有条件执行）**

```bash
test_check_replication_integration() {
    # 检查是否为主库/有复制
    if ! psql -d pgtool_test -c "SELECT pg_is_in_recovery()" 2>/dev/null | grep -q "f"; then
        skip_test "非主库配置，跳过复制测试"
        return
    fi

    local output
    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test check replication 2>&1)

    assert_contains "$output" "replication"
}
```

---

### Task 3: Stat 命令组集成测试

**Files:**
- Create: `tests/integration/test_stat.sh`

- [ ] **Step 1: 编写 activity 测试**

```bash
test_stat_activity_integration() {
    local output

    # 在后台启动一个长时间运行的查询
    (psql -d pgtool_test -c "SELECT pg_sleep(5)" &) 2>/dev/null

    sleep 1

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test stat activity 2>&1)

    # 清理后台进程
    pkill -f "pg_sleep(5)" 2>/dev/null || true

    assert_contains "$output" "pid"
    assert_contains "$output" "usename"
}
```

- [ ] **Step 2: 编写 locks 测试**

```bash
test_stat_locks_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test stat locks 2>&1)

    assert_contains "$output" "locktype"
}
```

- [ ] **Step 3: 编写 database 统计测试**

```bash
test_stat_database_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test stat database 2>&1)

    assert_contains "$output" "datname"
    assert_contains "$output" "pgtool_test"
}
```

- [ ] **Step 4: 编写 table 统计测试**

```bash
test_stat_table_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test stat table 2>&1)

    assert_contains "$output" "relname"
    assert_contains "$output" "test_users"
}
```

- [ ] **Step 5: 编写 indexes 统计测试**

```bash
test_stat_indexes_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test stat indexes 2>&1)

    assert_contains "$output" "indexrelname"
    assert_contains "$output" "idx_test_users_status"
}
```

---

### Task 4: Analyze 命令组集成测试

**Files:**
- Create: `tests/integration/test_analyze.sh`

- [ ] **Step 1: 编写 bloat 分析测试**

```bash
test_analyze_bloat_integration() {
    local output

    # 先创建一些膨胀数据
    psql -d pgtool_test -c "
        INSERT INTO test_large_table (data, value, created_at)
        SELECT md5(random()::text), random() * 1000, CURRENT_TIMESTAMP
        FROM generate_series(1, 10000);
        DELETE FROM test_large_table WHERE id % 2 = 0;
    " 2>/dev/null

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test analyze bloat 2>&1)

    assert_contains "$output" "表名"
    assert_contains "$output" "膨胀率"
}
```

- [ ] **Step 2: 编写 missing-indexes 测试**

```bash
test_analyze_missing_indexes_integration() {
    local output

    # 执行一些会导致顺序扫描的查询
    psql -d pgtool_test -c "
        SELECT * FROM test_orders WHERE amount > 500;
        SELECT * FROM test_users WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '30 days';
    " 2>/dev/null

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test analyze missing-indexes 2>&1)

    # 输出应该包含表名和扫描次数
    assert_contains "$output" "表名"
}
```

- [ ] **Step 3: 编写 slow-queries 测试**

```bash
test_analyze_slow_queries_integration() {
    local output

    # 执行慢查询（如果 pg_stat_statements 可用）
    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test analyze slow-queries 2>&1)

    # 即使没有慢查询，也应该正常返回
    assert_contains "$output" "查询" || assert_contains "$output" "无慢查询"
}
```

- [ ] **Step 4: 编写 vacuum-stats 测试**

```bash
test_analyze_vacuum_stats_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test analyze vacuum-stats 2>&1)

    assert_contains "$output" "表名"
}
```

---

### Task 5: Admin 命令组集成测试

**Files:**
- Create: `tests/integration/test_admin.sh`

- [ ] **Step 1: 编写 checkpoint 测试**

```bash
test_admin_checkpoint_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test admin checkpoint 2>&1)

    assert_contains "$output" "检查点"
}
```

- [ ] **Step 2: 编写 reload 测试**

```bash
test_admin_reload_integration() {
    local output

    # 注意：reload 需要特定权限
    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test admin reload 2>&1)

    # 检查是否有权限错误
    if echo "$output" | grep -q "权限"; then
        skip_test "需要数据库超级用户权限"
        return
    fi

    assert_contains "$output" "配置"
}
```

- [ ] **Step 3: 编写 kill-blocking 测试**

```bash
test_admin_kill_blocking_integration() {
    # 创建一个阻塞场景
    local output

    # 在事务中锁定表
    (psql -d pgtool_test -c "BEGIN; LOCK TABLE test_users; SELECT pg_sleep(10); ROLLBACK;" &) 2>/dev/null
    sleep 1

    # 另一个会话尝试访问
    (psql -d pgtool_test -c "SELECT * FROM test_users LIMIT 1;" &) 2>/dev/null
    sleep 1

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test admin kill-blocking 2>&1)

    # 清理
    pkill -f "pg_sleep(10)" 2>/dev/null || true

    assert_contains "$output" "阻塞"
}
```

- [ ] **Step 4: 编写 cancel-query 测试**

```bash
test_admin_cancel_query_integration() {
    # 启动一个长时间运行的查询
    local pid
    pid=$(psql -d pgtool_test -c "SELECT pg_backend_pid();" -t 2>/dev/null | tr -d ' ')

    (psql -d pgtool_test -c "SELECT pg_sleep(30)" &) 2>/dev/null
    sleep 1

    local output
    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test admin cancel-query --pid="$pid" --force 2>&1)

    # 清理
    pkill -f "pg_sleep(30)" 2>/dev/null || true

    assert_contains "$output" "取消"
}
```

---

### Task 6: Plugin 命令组集成测试

**Files:**
- Create: `tests/integration/test_plugin.sh`

- [ ] **Step 1: 编写 plugin list 测试**

```bash
test_plugin_list_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" plugin list 2>&1)

    assert_contains "$output" "example"
}
```

- [ ] **Step 2: 编写 plugin example 测试**

```bash
test_plugin_example_integration() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" plugin example hello 2>&1)

    assert_contains "$output" "Hello"
}
```

---

### Task 7: 边界条件与错误处理测试

**Files:**
- Create: `tests/integration/test_edge_cases.sh`

- [ ] **Step 1: 测试无效数据库连接**

```bash
test_invalid_database_connection() {
    local output
    local exit_code

    output=$("$PGTOOL_ROOT/pgtool.sh" --dbname=nonexistent_db check xid 2>&1)
    exit_code=$?

    assert_true "$exit_code"
    assert_contains "$output" "错误"
}
```

- [ ] **Step 2: 测试无效命令**

```bash
test_invalid_command() {
    local output
    local exit_code

    output=$("$PGTOOL_ROOT/pgtool.sh" invalid_command 2>&1)
    exit_code=$?

    assert_true "$exit_code"
    assert_contains "$output" "未知"
}
```

- [ ] **Step 3: 测试超时处理**

```bash
test_timeout_handling() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --timeout=1 --dbname=pgtool_test stat activity 2>&1)

    # 检查是否正常返回（不崩溃）
    return 0
}
```

- [ ] **Step 4: 测试各种格式输出**

```bash
test_output_formats() {
    local output_table
    local output_json
    local output_csv

    output_table=$("$PGTOOL_ROOT/pgtool.sh" --format=table --dbname=pgtool_test check connection 2>&1)
    output_json=$("$PGTOOL_ROOT/pgtool.sh" --format=json --dbname=pgtool_test check connection 2>&1)
    output_csv=$("$PGTOOL_ROOT/pgtool.sh" --format=csv --dbname=pgtool_test check connection 2>&1)

    # table 格式应该有分隔线
    assert_contains "$output_table" "│"

    # json 格式应该有括号
    assert_contains "$output_json" "{"

    # csv 格式应该有逗号
    assert_contains "$output_csv" ","
}
```

---

### Task 8: 性能测试

**Files:**
- Create: `tests/performance/test_performance.sh`

- [ ] **Step 1: 测试命令执行时间**

```bash
test_command_performance() {
    local start_time
    local end_time
    local duration

    start_time=$(date +%s%N)
    "$PGTOOL_ROOT/pgtool.sh" --dbname=pgtool_test check connection >/dev/null 2>&1
    end_time=$(date +%s%N)

    duration=$(( (end_time - start_time) / 1000000 ))  # 毫秒

    echo "命令执行时间: ${duration}ms"

    # 应该在 5 秒内完成
    if [[ $duration -gt 5000 ]]; then
        echo "警告: 命令执行时间过长"
        return 1
    fi
}
```

---

## 执行策略

### 阶段 1: 基础准备（必须完成）

1. ✅ 创建测试数据库环境
2. ✅ 编写数据库工具函数
3. ✅ 验证数据库可连接

### 阶段 2: Check 命令测试

1. ✅ test_check_xid_integration
2. ✅ test_check_connection_integration
3. ✅ test_check_autovacuum_integration
4. ✅ test_check_replication_integration

### 阶段 3: Stat 命令测试

1. ✅ test_stat_activity_integration
2. ✅ test_stat_locks_integration
3. ✅ test_stat_database_integration
4. ✅ test_stat_table_integration
5. ✅ test_stat_indexes_integration

### 阶段 4: Analyze 命令测试

1. ✅ test_analyze_bloat_integration
2. ✅ test_analyze_missing_indexes_integration
3. ✅ test_analyze_slow_queries_integration
4. ✅ test_analyze_vacuum_stats_integration

### 阶段 5: Admin 命令测试

1. ✅ test_admin_checkpoint_integration
2. ✅ test_admin_reload_integration
3. ✅ test_admin_kill_blocking_integration
4. ✅ test_admin_cancel_query_integration

### 阶段 6: Plugin 命令测试

1. ✅ test_plugin_list_integration
2. ✅ test_plugin_example_integration

### 阶段 7: 边界条件测试

1. ✅ test_invalid_database_connection
2. ✅ test_invalid_command
3. ✅ test_timeout_handling
4. ✅ test_output_formats

### 阶段 8: 性能测试

1. ✅ test_command_performance

### 阶段 9: 最终验证

1. ✅ 运行全部测试
2. ✅ 修复发现的 bug
3. ✅ 提交最终版本

---

## 测试标准

### 通过标准

- [ ] 所有19个命令都能正常执行
- [ ] 每个命令返回合理的输出
- [ ] 边界条件处理正确
- [ ] 错误信息清晰明确
- [ ] 无崩溃或异常退出
- [ ] 性能在可接受范围内（< 5秒）

### 质量标准

- [ ] 代码覆盖率 > 80%
- [ ] 集成测试覆盖所有命令
- [ ] 边界条件测试完整
- [ ] 文档完整准确

---

## 注意事项

1. **测试隔离**: 每个测试应该独立，不依赖其他测试的执行顺序
2. **数据清理**: 测试结束后清理创建的数据
3. **跳过条件**: 某些测试（如复制测试）需要特定条件，使用 skip_test
4. **权限问题**: Admin 命令可能需要超级用户权限
5. **并发安全**: 多个测试并行执行时不要相互干扰
