#!/bin/bash
# tests/test_cli.sh - 测试 CLI 功能

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

# 加载 CLI 模块
source "$PGTOOL_ROOT/lib/cli.sh"

#==============================================================================
# 命令组测试
#==============================================================================

test_groups_defined() {
    local count=${#PGTOOL_GROUPS[@]}

    # 检查至少有一些命令组
    [[ $count -ge 4 ]] && assert_true "0" || assert_true "1"

    # 检查关键命令组存在
    array_contains "check" "${PGTOOL_GROUPS[@]}" && assert_true "0" || assert_true "1"
    array_contains "stat" "${PGTOOL_GROUPS[@]}" && assert_true "0" || assert_true "1"
    array_contains "admin" "${PGTOOL_GROUPS[@]}" && assert_true "0" || assert_true "1"
}

test_group_desc() {
    local desc

    desc=$(pgtool_group_desc "check")
    assert_contains "$desc" "健康"

    desc=$(pgtool_group_desc "stat")
    assert_contains "$desc" "统计"
}

#==============================================================================
# 命令存在性测试
#==============================================================================

test_command_exists() {
    # 测试存在的命令
    pgtool_command_exists "check" "xid" && assert_true "0" || assert_true "1"
    pgtool_command_exists "stat" "activity" && assert_true "0" || assert_true "1"

    # 测试不存在的命令
    pgtool_command_exists "check" "nonexistent" && assert_true "1" || assert_true "0"
    pgtool_command_exists "nonexistent" "xid" && assert_true "1" || assert_true "0"
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "cli.sh 测试:"

run_test "test_groups_defined" "test_groups_defined"
run_test "test_group_desc" "test_group_desc"
run_test "test_command_exists" "test_command_exists"

# 运行清理并输出汇总
teardown
