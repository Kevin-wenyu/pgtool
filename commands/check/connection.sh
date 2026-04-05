#!/bin/bash
# commands/check/connection.sh - 检查连接数使用情况

pgtool_check_connection() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_connection_help
                return 0
                ;;
            --threshold)
                shift
                PGTOOL_CONN_THRESHOLD="$1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "connection"); then
        pgtool_fatal "SQL文件未找到: check/connection"
    fi

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    pgtool_info "连接数使用情况:"
    echo ""
    echo "$result"

    # 检查使用率（仅在表格格式下）
    if [[ "${PGTOOL_FORMAT:-table}" == "table" ]] || [[ "${PGTOOL_FORMAT:-}" == "aligned" ]]; then
        local usage
        usage=$(echo "$result" | grep -E '^\|' | grep -v 'Max' | awk -F'|' '{print $8}' | tr -d ' %' | head -1)
        local threshold="${PGTOOL_CONN_THRESHOLD:-80}"

        if [[ -n "$usage" ]] && [[ "$usage" != "N/A" ]] && command -v bc >/dev/null 2>&1; then
            if (( $(echo "$usage > $threshold" | bc -l) )); then
                pgtool_warn "连接使用率超过 ${threshold}%: ${usage}%"
                return 1
            fi
        fi
    fi

    return 0
}

pgtool_check_connection_help() {
    cat <<EOF
检查连接数使用情况

显示数据库连接的使用情况：
- 最大连接数限制
- 当前连接数
- 活跃连接数
- 空闲连接数
- 事务中空闲连接数
- 等待中的连接数
- 使用百分比

用法: pgtool check connection [选项]

选项:
  -h, --help          显示帮助
      --threshold N   警告阈值百分比 (默认: 80)

示例:
  pgtool check connection
  pgtool check connection --threshold=90
EOF
}
