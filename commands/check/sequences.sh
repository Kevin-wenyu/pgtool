#!/bin/bash
# commands/check/sequences.sh - 检查序列使用情况

#==============================================================================
# 默认阈值
#==============================================================================

PGTOOL_SEQUENCES_WARNING="${PGTOOL_SEQUENCES_WARNING:-80}"
PGTOOL_SEQUENCES_CRITICAL="${PGTOOL_SEQUENCES_CRITICAL:-95}"

#==============================================================================
# 主函数
#==============================================================================

pgtool_check_sequences() {
    local threshold_warning="$PGTOOL_SEQUENCES_WARNING"
    local threshold_critical="$PGTOOL_SEQUENCES_CRITICAL"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_sequences_help
                return $EXIT_SUCCESS
                ;;
            --threshold-warning)
                shift
                threshold_warning="$1"
                shift
                ;;
            --threshold-critical)
                shift
                threshold_critical="$1"
                shift
                ;;
            -*)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "检查序列使用情况..."
    pgtool_info "警告阈值: ${threshold_warning}%"
    pgtool_info "危险阈值: ${threshold_critical}%"
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "sequences"); then
        pgtool_fatal "SQL文件未找到: check/sequences"
    fi

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 执行 SQL
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # 显示结果
    echo "$result"

    # 检查是否有警告 - 使用实际阈值判断
    local max_usage
    max_usage=$(echo "$result" | grep -E '^\s*\|' | tail -n +2 | head -n -1 | awk -F'|' '{print $8}' | sed 's/ //g' | sort -rn | head -1)

    if [[ -n "$max_usage" && "$max_usage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        if (( $(echo "$max_usage >= $threshold_critical" | bc -l 2>/dev/null || echo "0") )); then
            return $EXIT_INVALID_ARGS
        elif (( $(echo "$max_usage >= $threshold_warning" | bc -l 2>/dev/null || echo "0") )); then
            return $EXIT_GENERAL_ERROR
        fi
    fi

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_check_sequences_help() {
    cat <<EOF
检查序列使用情况

检查数据库序列是否接近最大值，预警序列耗尽风险。

用法: pgtool check sequences [选项]

选项:
  -h, --help                   显示帮助
      --threshold-warning NUM  警告阈值百分比 (默认: 80)
      --threshold-critical NUM 危险阈值百分比 (默认: 95)

环境变量:
  PGTOOL_SEQUENCES_WARNING     警告阈值
  PGTOOL_SEQUENCES_CRITICAL    危险阈值

输出:
  OK       - 序列使用正常
  WARNING  - 序列使用超过警告阈值
  CRITICAL - 序列使用接近危险值，需要立即处理

示例:
  pgtool check sequences
  pgtool check sequences --threshold-warning=70 --threshold-critical=90
EOF
}
