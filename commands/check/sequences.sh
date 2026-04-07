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
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_sequences_help
                return 0
                ;;
            --threshold-warning)
                shift
                PGTOOL_SEQUENCES_WARNING="$1"
                shift
                ;;
            --threshold-critical)
                shift
                PGTOOL_SEQUENCES_CRITICAL="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "检查序列使用情况..."
    pgtool_info "警告阈值: ${PGTOOL_SEQUENCES_WARNING}%"
    pgtool_info "危险阈值: ${PGTOOL_SEQUENCES_CRITICAL}%"
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
        --variable="threshold_warning=$PGTOOL_SEQUENCES_WARNING" \
        --variable="threshold_critical=$PGTOOL_SEQUENCES_CRITICAL" \
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

    # 检查是否有警告
    if echo "$result" | grep -q "CRITICAL"; then
        return 2
    elif echo "$result" | grep -q "WARNING"; then
        return 1
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
