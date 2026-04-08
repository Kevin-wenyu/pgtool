#!/bin/bash
# tests/test_kill_blocking_audit.sh - 测试 kill_blocking 审计日志

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

#==============================================================================
# 审计日志测试
#==============================================================================

test_kill_blocking_has_audit_call() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/admin/kill_blocking.sh")
    assert_contains "$content" "pgtool_audit_admin"
}

test_kill_blocking_audit_in_bulk_termination() {
    # 检查批量终止代码块（127-154行）是否有审计日志
    local block
    block=$(sed -n '127,154p' "$PGTOOL_ROOT/commands/admin/kill_blocking.sh")

    if echo "$block" | grep -q "pgtool_audit"; then
        assert_true "0"
    else
        # BUG：批量终止时没有审计日志
        assert_true "1"
    fi
}

test_kill_blocking_single_if_for_target_pid() {
    # 检查第90-125行范围内只有一个 [[ -n "$target_pid" ]]
    local block
    block=$(sed -n '90,125p' "$PGTOOL_ROOT/commands/admin/kill_blocking.sh")

    local count
    count=$(echo "$block" | grep -c '\[\[ -n "\$target_pid"')

    if [[ "$count" -eq 1 ]]; then
        assert_true "0"
    else
        # BUG：有重复判断
        assert_true "1"
    fi
}

#==============================================================================
# 运行测试
#==============================================================================

echo ""
echo "kill-blocking 审计日志测试:"

run_test "test_kill_blocking_has_audit_call" "审计日志调用存在"
run_test "test_kill_blocking_audit_in_bulk_termination" "批量终止有审计日志（预期失败）"
run_test "test_kill_blocking_single_if_for_target_pid" "无重复if判断（预期失败）"
