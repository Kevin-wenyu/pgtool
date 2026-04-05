#!/bin/bash
# tests/test_core.sh - 测试 core.sh 中的常量

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

#==============================================================================
# 版本测试
#==============================================================================

test_version_defined() {
    assert_not_empty "$PGTOOL_VERSION"
    assert_contains "$PGTOOL_VERSION" "."
}

test_name_defined() {
    assert_not_empty "$PGTOOL_NAME"
    assert_equals "pgtool" "$PGTOOL_NAME"
}

#==============================================================================
# 退出码测试
#==============================================================================

test_exit_codes() {
    assert_equals "0" "$EXIT_SUCCESS"
    assert_equals "1" "$EXIT_GENERAL_ERROR"
    assert_equals "2" "$EXIT_INVALID_ARGS"
    assert_equals "3" "$EXIT_CONNECTION_ERROR"
    assert_equals "4" "$EXIT_TIMEOUT"
    assert_equals "5" "$EXIT_SQL_ERROR"
}

#==============================================================================
# 默认值测试
#==============================================================================

test_defaults() {
    assert_equals "30" "$PGTOOL_DEFAULT_TIMEOUT"
    assert_equals "table" "$PGTOOL_DEFAULT_FORMAT"
    assert_equals "INFO" "$PGTOOL_DEFAULT_LOG_LEVEL"
}

#==============================================================================
# 颜色代码测试
#==============================================================================

test_color_codes() {
    assert_not_empty "$COLOR_RED"
    assert_not_empty "$COLOR_GREEN"
    assert_not_empty "$COLOR_YELLOW"
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "core.sh 测试:"

run_test "test_version_defined" "test_version_defined"
run_test "test_name_defined" "test_name_defined"
run_test "test_exit_codes" "test_exit_codes"
run_test "test_defaults" "test_defaults"
run_test "test_color_codes" "test_color_codes"

# 运行清理并输出汇总
teardown
