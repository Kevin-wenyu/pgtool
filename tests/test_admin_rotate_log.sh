#!/bin/bash
# tests/test_admin_rotate_log.sh - 测试 rotate-log 命令

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

#==============================================================================
# rotate-log 命令测试
#==============================================================================

test_rotate_log_command_exists() {
    if [[ -f "$PGTOOL_ROOT/commands/admin/rotate_log.sh" ]]; then
        assert_true "0"
    else
        assert_true "1"
    fi
}

test_rotate_log_sql_exists() {
    if [[ -f "$PGTOOL_ROOT/sql/admin/rotate_log.sql" ]]; then
        assert_true "0"
    else
        assert_true "1"
    fi
}

test_rotate_log_help() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" admin rotate-log --help 2>&1)

    assert_contains "$output" "rotate-log"
    assert_contains "$output" "pg_rotate_logfile"
}

test_rotate_log_registered_in_index() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" admin --help 2>&1)

    assert_contains "$output" "rotate-log"
    assert_contains "$output" "轮换日志文件"
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "rotate-log 命令测试:"

run_test "test_rotate_log_command_exists" "test_rotate_log_command_exists"
run_test "test_rotate_log_sql_exists" "test_rotate_log_sql_exists"
run_test "test_rotate_log_help" "test_rotate_log_help"
run_test "test_rotate_log_registered_in_index" "test_rotate_log_registered_in_index"
