#!/bin/bash
# tests/run.sh - 测试入口

set -euo pipefail

# 获取脚本路径
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PGTOOL_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# 颜色
color_green='\033[0;32m'
color_red='\033[0;31m'
color_yellow='\033[0;33m'
color_reset='\033[0m'

# 统计
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# 运行单个测试文件
run_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)

    echo ""
    echo "========================================"
    echo "运行: $test_name"
    echo "========================================"

    # 运行测试并捕获结果
    local output
    local exit_code=0

    if output=$(bash "$test_file" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    echo "$output"

    # 解析结果
    local passed=$(echo "$output" | grep -oE '通过: [0-9]+' | grep -oE '[0-9]+' || echo 0)
    local failed=$(echo "$output" | grep -oE '失败: [0-9]+' | grep -oE '[0-9]+' || echo 0)
    local skipped=$(echo "$output" | grep -oE '跳过: [0-9]+' | grep -oE '[0-9]+' || echo 0)

    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped))

    return $exit_code
}

# 主函数
main() {
    echo "pgtool 测试套件"
    echo "==============="
    echo ""
    echo "项目路径: $PGTOOL_ROOT"
    echo "测试路径: $TEST_DIR"
    echo ""

    local start_time=$(date +%s)

    # 运行所有单元测试文件
    local test_file
    for test_file in "$TEST_DIR"/test_*.sh; do
        [[ -f "$test_file" ]] || continue
        [[ "$(basename "$test_file")" == "test_runner.sh" ]] && continue

        run_test_file "$test_file" || true
    done

    # 运行集成测试（如果有数据库连接）
    if [[ -f "$TEST_DIR/integration_test.sh" ]]; then
        if psql -d postgres -c "SELECT 1" >/dev/null 2>&1; then
            echo ""
            echo "========================================"
            echo "运行: integration_test"
            echo "========================================"

            local output
            local exit_code=0

            if output=$(bash "$TEST_DIR/integration_test.sh" 2>&1); then
                exit_code=0
            else
                exit_code=$?
            fi

            echo "$output"

            # 解析结果
            local passed=$(echo "$output" | grep -oE '通过: [0-9]+' | tail -1 | grep -oE '[0-9]+' || echo 0)
            local failed=$(echo "$output" | grep -oE '失败: [0-9]+' | tail -1 | grep -oE '[0-9]+' || echo 0)
            local skipped=$(echo "$output" | grep -oE '跳过: [0-9]+' | tail -1 | grep -oE '[0-9]+' || echo 0)

            TOTAL_PASSED=$((TOTAL_PASSED + passed))
            TOTAL_FAILED=$((TOTAL_FAILED + failed))
            TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped))
        else
            echo ""
            echo -e "${color_yellow}跳过集成测试: 无法连接到 PostgreSQL${color_reset}"
        fi
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 显示汇总
    echo ""
    echo "========================================"
    echo "              测试汇总"
    echo "========================================"
    echo -e "  ${color_green}通过: $TOTAL_PASSED${color_reset}"
    [[ $TOTAL_FAILED -gt 0 ]] && echo -e "  ${color_red}失败: $TOTAL_FAILED${color_reset}" || echo "  失败: $TOTAL_FAILED"
    [[ $TOTAL_SKIPPED -gt 0 ]] && echo -e "  ${color_yellow}跳过: $TOTAL_SKIPPED${color_reset}" || echo "  跳过: $TOTAL_SKIPPED"
    echo "  总计: $((TOTAL_PASSED + TOTAL_FAILED + TOTAL_SKIPPED))"
    echo "  用时: ${duration}s"
    echo "========================================"

    if [[ $TOTAL_FAILED -gt 0 ]]; then
        echo -e "${color_red}测试失败!${color_reset}"
        exit 1
    else
        echo -e "${color_green}所有测试通过!${color_reset}"
        exit 0
    fi
}

# 显示帮助
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    echo "pgtool 测试套件"
    echo ""
    echo "用法:"
    echo "  ./run.sh              运行所有测试"
    echo "  ./run.sh test_util    运行特定测试文件"
    echo "  ./run.sh integration  运行集成测试"
    echo ""
    echo "测试文件:"
    for f in "$TEST_DIR"/test_*.sh; do
        [[ -f "$f" ]] || continue
        [[ "$(basename "$f")" == "test_runner.sh" ]] && continue
        echo "  - $(basename "$f" .sh)"
    done
    echo "  - integration_test"
    exit 0
fi

# 运行特定测试
if [[ -n "${1:-}" ]]; then
    if [[ "$1" == "integration" ]]; then
        if [[ -f "$TEST_DIR/integration_test.sh" ]]; then
            bash "$TEST_DIR/integration_test.sh"
            exit $?
        else
            echo "错误: 集成测试文件不存在"
            exit 1
        fi
    fi

    test_file="$TEST_DIR/$1.sh"
    if [[ -f "$test_file" ]]; then
        bash "$test_file"
        exit $?
    else
        echo "错误: 测试文件不存在: $test_file"
        exit 1
    fi
fi

# 运行所有测试
main "$@"
