#!/bin/bash
# tests/test_analyze_index_usage.sh - 测试 index-usage 分析命令

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

#==============================================================================
# 文件存在性测试
#==============================================================================

test_index_usage_sql_exists() {
    if [[ -f "$PGTOOL_ROOT/sql/analyze/index_usage.sql" ]]; then
        assert_true "0"
    else
        assert_true "1"
    fi
}

test_index_usage_command_exists() {
    if [[ -f "$PGTOOL_ROOT/commands/analyze/index_usage.sh" ]]; then
        assert_true "0"
    else
        assert_true "1"
    fi
}

#==============================================================================
# 帮助测试
#==============================================================================

test_index_usage_help() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" analyze index-usage --help 2>&1)

    assert_contains "$output" "索引"
    assert_contains "$output" "用法"
}

#==============================================================================
# 分析命令帮助包含 index-usage
#==============================================================================

test_analyze_help_includes_index_usage() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" analyze --help 2>&1)

    assert_contains "$output" "index-usage"
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "index-usage 分析命令测试:"

run_test "test_index_usage_sql_exists" "test_index_usage_sql_exists"
run_test "test_index_usage_command_exists" "test_index_usage_command_exists"
run_test "test_index_usage_help" "test_index_usage_help"
run_test "test_analyze_help_includes_index_usage" "test_analyze_help_includes_index_usage"

# 运行清理并输出汇总
teardown
