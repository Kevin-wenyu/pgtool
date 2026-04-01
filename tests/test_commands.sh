#!/bin/bash
# tests/test_commands.sh - 测试实际命令

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

#==============================================================================
# 帮助命令测试
#==============================================================================

test_help_command() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --help 2>&1)

    assert_contains "$output" "pgtool"
    assert_contains "$output" "用法"
    assert_contains "$output" "check"
    assert_contains "$output" "stat"
}

test_version_command() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" --version 2>&1)

    assert_contains "$output" "$PGTOOL_VERSION"
}

test_check_help() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" check --help 2>&1)

    assert_contains "$output" "xid"
}

test_stat_help() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" stat --help 2>&1)

    assert_contains "$output" "activity"
}

#==============================================================================
# 命令存在性测试
#==============================================================================

test_commands_exist() {
    local cmd
    local missing=()

    # 检查关键命令文件是否存在
    for cmd in check/xid check/connection stat/activity stat/locks admin/checkpoint admin/reload analyze/bloat; do
        if [[ ! -f "$PGTOOL_ROOT/commands/$cmd.sh" ]]; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "缺失命令: ${missing[*]}" >&2
        return 1
    fi
}

test_sql_files_exist() {
    local sql
    local missing=()

    # 检查关键 SQL 文件是否存在
    for sql in check/xid check/connection stat/activity; do
        if [[ ! -f "$PGTOOL_ROOT/sql/$sql.sql" ]]; then
            missing+=("$sql")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "缺失 SQL: ${missing[*]}" >&2
        return 1
    fi
}

#==============================================================================
# 配置文件测试
#==============================================================================

test_config_file_exists() {
    [[ -f "$PGTOOL_ROOT/conf/pgtool.conf" ]] && assert_true "0" || assert_true "1"
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "命令测试:"

run_test "test_help_command" "test_help_command"
run_test "test_version_command" "test_version_command"
run_test "test_check_help" "test_check_help"
run_test "test_stat_help" "test_stat_help"
run_test "test_commands_exist" "test_commands_exist"
run_test "test_sql_files_exist" "test_sql_files_exist"
run_test "test_config_file_exists" "test_config_file_exists"
