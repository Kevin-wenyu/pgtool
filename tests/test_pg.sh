#!/bin/bash
# tests/test_pg.sh - 测试 PostgreSQL 连接功能

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

# 加载 pg 模块
source "$PGTOOL_ROOT/lib/pg.sh"

#==============================================================================
# 连接选项测试
#==============================================================================

test_pg_init() {
    # 重新初始化
    pgtool_pg_init

    # 检查连接选项数组是否被设置
    [[ ${#PGTOOL_CONN_OPTS[@]} -gt 0 ]] && assert_true "0" || assert_true "1"

    # 检查关键选项是否存在
    local opts="${PGTOOL_CONN_OPTS[*]}"
    assert_contains "$opts" "--host"
    assert_contains "$opts" "--port"
}

test_pg_find_sql() {
    local sql_file

    # 测试存在的 SQL 文件
    sql_file=$(pgtool_pg_find_sql "check" "xid")
    [[ -f "$sql_file" ]] && assert_true "0" || assert_true "1"

    # 测试不存在的 SQL 文件
    ! pgtool_pg_find_sql "check" "nonexistent" 2>/dev/null && assert_true "0" || assert_true "1"
}

#==============================================================================
# 连接测试（需要数据库）
#==============================================================================

test_pg_connection() {
    # 尝试连接（可能失败，但不影响测试）
    if pgtool_pg_test_connection >/dev/null 2>&1; then
        assert_true "0"
    else
        skip_test "无法连接到数据库"
    fi
}

test_pg_version() {
    if pgtool_pg_test_connection >/dev/null 2>&1; then
        local version
        version=$(pgtool_pg_version)
        assert_not_empty "$version"
        assert_contains "$version" "PostgreSQL"
    else
        skip_test "无法连接到数据库"
    fi
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "pg.sh 测试:"

run_test "test_pg_init" "test_pg_init"
run_test "test_pg_find_sql" "test_pg_find_sql"
run_test "test_pg_connection" "test_pg_connection"
run_test "test_pg_version" "test_pg_version"

# 运行清理并输出汇总
teardown
