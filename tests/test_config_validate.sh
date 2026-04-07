#!/bin/bash
# tests/test_config_validate.sh - 测试 config validate 命令

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

#==============================================================================
# 文件存在性测试
#==============================================================================

test_config_validate_sql_exists() {
    if [[ -f "$PGTOOL_ROOT/sql/config/validate.sql" ]]; then
        assert_true "0"
    else
        assert_true "1"
    fi
}

test_config_validate_command_exists() {
    if [[ -f "$PGTOOL_ROOT/commands/config/validate.sh" ]]; then
        assert_true "0"
    else
        assert_true "1"
    fi
}

#==============================================================================
# 命令注册测试
#==============================================================================

test_config_validate_registered() {
    local output
    output=$("$PGTOOL_ROOT/pgtool.sh" config --help 2>&1)
    assert_contains "$output" "validate"
}

test_config_validate_help() {
    local output
    output=$("$PGTOOL_ROOT/pgtool.sh" config validate --help 2>&1)
    assert_contains "$output" "验证"
    assert_contains "$output" "max_connections"
    assert_contains "$output" "shared_buffers"
    assert_contains "$output" "work_mem"
}

#==============================================================================
# SQL 语法测试
#==============================================================================

test_config_validate_sql_syntax() {
    # 检查 SQL 文件中是否包含必需的参数
    local sql_content
    sql_content=$(cat "$PGTOOL_ROOT/sql/config/validate.sql")
    assert_contains "$sql_content" "max_connections"
    assert_contains "$sql_content" "shared_buffers"
    assert_contains "$sql_content" "work_mem"
    assert_contains "$sql_content" "autovacuum"
    assert_contains "$sql_content" "logging_collector"
    assert_contains "$sql_content" "track_activities"
    assert_contains "$sql_content" "OK"
    assert_contains "$sql_content" "WARNING"
    assert_contains "$sql_content" "CRITICAL"
}

#==============================================================================
# 命令实现测试
#==============================================================================

test_config_validate_function_exists() {
    # 检查函数名是否存在于命令文件中
    local cmd_content
    cmd_content=$(cat "$PGTOOL_ROOT/commands/config/validate.sh")
    assert_contains "$cmd_content" "pgtool_config_validate"
}

test_config_validate_help_function_exists() {
    local cmd_content
    cmd_content=$(cat "$PGTOOL_ROOT/commands/config/validate.sh")
    assert_contains "$cmd_content" "pgtool_config_validate_help"
}

#==============================================================================
# 运行测试
#==============================================================================

echo ""
echo "config validate 命令测试:"

run_test "validate_sql_exists" test_config_validate_sql_exists
run_test "validate_command_exists" test_config_validate_command_exists
run_test "validate_registered" test_config_validate_registered
run_test "validate_help" test_config_validate_help
run_test "validate_sql_syntax" test_config_validate_sql_syntax
run_test "validate_function_exists" test_config_validate_function_exists
run_test "validate_help_function_exists" test_config_validate_help_function_exists

# 运行清理并输出汇总
teardown
