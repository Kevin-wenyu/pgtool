#!/bin/bash
# tests/test_runner.sh - 测试运行器

set -euo pipefail

# 脚本路径
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PGTOOL_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# 加载被测试的库
source "$PGTOOL_ROOT/lib/core.sh"
source "$PGTOOL_ROOT/lib/log.sh"
source "$PGTOOL_ROOT/lib/util.sh"

#==============================================================================
# 测试框架
#==============================================================================

# 测试结果统计
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# 当前测试名称
CURRENT_TEST=""

# 测试开始时间
TEST_START_TIME=0

# 测试初始化
setup() {
    TEST_START_TIME=$(date +%s)
    pgtool_info "开始测试..."
    echo ""
}

# 测试清理
teardown() {
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))

    echo ""
    echo "======================================"
    echo "测试结果:"
    echo "  通过: $TESTS_PASSED"
    echo "  失败: $TESTS_FAILED"
    echo "  跳过: $TESTS_SKIPPED"
    echo "  总计: $((TESTS_PASSED + TEST_FAILED + TESTS_SKIPPED))"
    echo "  用时: ${duration}s"
    echo "======================================"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

# 运行单个测试
run_test() {
    local test_name="$1"
    local test_func="$2"

    CURRENT_TEST="$test_name"

    echo -n "  $test_name ... "

    if ! type "$test_func" &>/dev/null; then
        echo "SKIP (函数未定义)"
        ((TESTS_SKIPPED++))
        return
    fi

    # 捕获测试输出
    local output
    local exit_code=0

    if output=$("$test_func" 2>&1); then
        echo "PASS"
        ((TESTS_PASSED++))
    else
        echo "FAIL"
        echo "    输出: $output"
        ((TESTS_FAILED++))
    fi
}

# 断言函数
assert_equals() {
    local expected="$1"
    local actual="$2"

    if [[ "$expected" != "$actual" ]]; then
        echo "断言失败: 期望值 '$expected'，实际值 '$actual'" >&2
        return 1
    fi
}

assert_true() {
    local result="$1"

    if [[ "$result" != "0" ]] && [[ "$result" != "true" ]] && [[ "$result" != "yes" ]]; then
        echo "断言失败: 期望为真，实际为 '$result'" >&2
        return 1
    fi
}

assert_false() {
    local result="$1"

    if [[ "$result" == "0" ]] || [[ "$result" == "true" ]] || [[ "$result" == "yes" ]]; then
        echo "断言失败: 期望为假，实际为 '$result'" >&2
        return 1
    fi
}

assert_not_empty() {
    local value="$1"

    if [[ -z "$value" ]]; then
        echo "断言失败: 期望非空值" >&2
        return 1
    fi
}

assert_empty() {
    local value="$1"

    if [[ -n "$value" ]]; then
        echo "断言失败: 期望空值，实际为 '$value'" >&2
        return 1
    fi
}

assert_contains() {
    local str="$1"
    local substr="$2"

    if [[ "$str" != *"$substr"* ]]; then
        echo "断言失败: '$str' 不包含 '$substr'" >&2
        return 1
    fi
}

# 跳过测试
skip_test() {
    local reason="${1:-}"
    echo "SKIP${reason:+ ($reason)}"
    ((TESTS_SKIPPED++))
    return 0
}

#==============================================================================
# 加载测试文件
#==============================================================================

load_tests() {
    local test_file="$1"

    if [[ ! -f "$test_file" ]]; then
        pgtool_error "测试文件不存在: $test_file"
        return 1
    fi

    source "$test_file"
}

#==============================================================================
# 主函数
#==============================================================================

main() {
    setup

    # 加载所有测试文件
    local test_file
    for test_file in "$TEST_DIR"/test_*.sh; do
        [[ -f "$test_file" ]] || continue
        [[ "$(basename "$test_file")" == "test_runner.sh" ]] && continue

        echo "加载测试: $(basename "$test_file")"
        load_tests "$test_file"
    done

    teardown
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
