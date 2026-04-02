#!/bin/bash
# tests/test_user.sh - 测试用户命令组

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

# 测试初始化 - 加载 user 模块和 cli 模块
setup_user_tests() {
    # 加载 cli.sh 以获取 PGTOOL_GROUPS
    if [[ -z "${PGTOOL_GROUPS:-}" ]]; then
        source "$PGTOOL_ROOT/lib/cli.sh" 2>/dev/null || true
    fi

    # 加载 user.sh
    if ! type pgtool_user_list_all &>/dev/null; then
        source "$PGTOOL_ROOT/lib/user.sh" 2>/dev/null || true
    fi
}

# 运行初始化
setup_user_tests

#==============================================================================
# 库加载测试
#==============================================================================

test_user_lib_loaded() {
    # 检查关键函数是否存在
    assert_true "$(type pgtool_user_list_all &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_get_info &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_get_membership &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_get_members &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_has_db_permission &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_has_table_permission &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_count_superusers &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_activity_summary &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_build_tree &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_format_bool &>/dev/null && echo "0" || echo "1")"
    assert_true "$(type pgtool_user_format_tree &>/dev/null && echo "0" || echo "1")"
}

#==============================================================================
# 格式化函数测试
#==============================================================================

test_user_format_bool() {
    # 测试 true 值
    local result
    result=$(pgtool_user_format_bool "t")
    assert_equals "$result" "Yes"

    result=$(pgtool_user_format_bool "true")
    assert_equals "$result" "Yes"

    result=$(pgtool_user_format_bool "1")
    assert_equals "$result" "Yes"

    result=$(pgtool_user_format_bool "yes")
    assert_equals "$result" "Yes"

    # 测试 false 值
    result=$(pgtool_user_format_bool "f")
    assert_equals "$result" "No"

    result=$(pgtool_user_format_bool "false")
    assert_equals "$result" "No"

    result=$(pgtool_user_format_bool "0")
    assert_equals "$result" "No"

    result=$(pgtool_user_format_bool "no")
    assert_equals "$result" "No"

    # 测试其他值（原样返回）
    result=$(pgtool_user_format_bool "maybe")
    assert_equals "$result" "maybe"
}

#==============================================================================
# 命令文件存在性测试
#==============================================================================

test_user_commands_exist() {
    local cmd
    local missing=()

    # 检查所有用户命令文件是否存在
    for cmd in user/index user/list user/info user/permissions user/activity user/audit user/tree; do
        if [[ ! -f "$PGTOOL_ROOT/commands/$cmd.sh" ]]; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "缺失命令: ${missing[*]}" >&2
        return 1
    fi
}

#==============================================================================
# SQL 文件存在性测试
#==============================================================================

test_user_sql_files_exist() {
    local sql
    local missing=()

    # 检查所有用户 SQL 文件是否存在
    for sql in user/list user/info user/activity user/permissions_database user/permissions_tables user/audit_superusers user/membership; do
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
# CLI 注册测试
#==============================================================================

test_user_registered_in_cli() {
    # 检查 user 是否在 PGTOOL_GROUPS 中
    local found="false"
    local group
    for group in "${PGTOOL_GROUPS[@]}"; do
        if [[ "$group" == "user" ]]; then
            found="true"
            break
        fi
    done
    assert_true "$found"
}

#==============================================================================
# 用户命令帮助测试
#==============================================================================

test_user_help() {
    local output

    output=$("$PGTOOL_ROOT/pgtool.sh" user --help 2>&1)

    assert_contains "$output" "list"
    assert_contains "$output" "info"
    assert_contains "$output" "permissions"
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "user 命令组测试:"

run_test "test_user_lib_loaded" "test_user_lib_loaded"
run_test "test_user_format_bool" "test_user_format_bool"
run_test "test_user_commands_exist" "test_user_commands_exist"
run_test "test_user_sql_files_exist" "test_user_sql_files_exist"
run_test "test_user_registered_in_cli" "test_user_registered_in_cli"
run_test "test_user_help" "test_user_help"

# 运行清理并输出汇总
teardown
