#!/bin/bash
# commands/stat/activity.sh - 查看活动会话

pgtool_stat_activity() {
    local -a opts=()
    local limit=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_activity_help
                return 0
                ;;
            -l|--limit)
                shift
                limit="LIMIT $1"
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                # 全局选项，跳过参数值
                shift
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "stat" "activity"); then
        pgtool_fatal "SQL文件未找到: stat/activity"
    fi

    # 测试连接
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
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

    # 检查是否有活动查询
    local row_count
    row_count=$(echo "$result" | grep -c '^|' 2>/dev/null | head -1 || echo 0)

    if [[ $row_count -le 2 ]]; then
        pgtool_info "当前没有活动会话"
        return 0
    fi

    pgtool_info "当前活动会话 (不含当前连接):"
    echo ""
    echo "$result"
}

pgtool_stat_activity_help() {
    cat <<EOF
查看当前活动会话

显示所有非当前连接的会话信息，包括：
- PID, 用户名, 数据库
- 连接来源
- 会话状态 (active/idle/...)
- 执行时间
- 正在执行的查询

用法: pgtool stat activity [选项]

选项:
  -h, --help       显示帮助
  -l, --limit N    限制显示行数

示例:
  pgtool stat activity
  pgtool stat activity --limit=10
EOF
}
