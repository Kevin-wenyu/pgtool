#!/bin/bash
# commands/check/long_tx.sh - 检查长事务

#==============================================================================
# 默认阈值
#==============================================================================

PGTOOL_LONG_TX_THRESHOLD="${PGTOOL_LONG_TX_THRESHOLD:-5}"

#==============================================================================
# 主函数
#==============================================================================

pgtool_check_long_tx() {
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_long_tx_help
                return 0
                ;;
            --threshold)
                shift
                PGTOOL_LONG_TX_THRESHOLD="$1"
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
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "检查长事务..."
    pgtool_info "阈值: ${PGTOOL_LONG_TX_THRESHOLD} 分钟"
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "long_tx"); then
        pgtool_fatal "SQL文件未找到: check/long_tx"
    fi

    # 测试连接（静默）
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 替换阈值参数
    local sql_content
    sql_content=$(sed "s/:threshold/${PGTOOL_LONG_TX_THRESHOLD}/g" "$sql_file")

    # 执行 SQL
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(echo "$sql_content" | timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
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

    # 检查是否有长事务
    local count
    count=$(echo "$result" | grep -c "^[[:space:]]*[0-9]" 2>/dev/null || echo "0")
    count=$(echo "$count" | tr -d '\n')

    if [[ $count -gt 0 ]]; then
        pgtool_warn "发现 ${count} 个运行超过 ${PGTOOL_LONG_TX_THRESHOLD} 分钟的事务"
        return 1
    fi

    pgtool_info "未发现超过 ${PGTOOL_LONG_TX_THRESHOLD} 分钟的长事务"
    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_check_long_tx_help() {
    cat <<EOF
检查长事务

查找运行时间超过阈值的事务。长事务会：
  - 阻止 VACUUM 清理死亡元组，导致表膨胀
  - 增加 XID 年龄，加速 XID 回卷风险
  - 持有锁资源，可能导致阻塞

推荐阈值：
  - OLTP 系统: 5-10 分钟
  - 批处理系统: 30-60 分钟
  - 报表查询: 根据业务容忍度设置

用法: pgtool check long-tx [选项]

选项:
  -h, --help       显示帮助
      --threshold NUM   时间阈值，单位分钟 (默认: 5)

环境变量:
  PGTOOL_LONG_TX_THRESHOLD  默认时间阈值

输出:
  显示超过阈值的事务信息，包括PID、用户、数据库、持续时间等

示例:
  pgtool check long-tx
  pgtool check long-tx --threshold=10
  pgtool check long-tx --threshold=30 --format=json
EOF
}
