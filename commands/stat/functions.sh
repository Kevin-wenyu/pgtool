#!/bin/bash
# commands/stat/functions.sh - 查看函数调用统计

pgtool_stat_functions() {
    local -a opts=()
    local limit=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_functions_help
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
    if ! sql_file=$(pgtool_pg_find_sql "stat" "functions"); then
        pgtool_fatal "SQL文件未找到: stat/functions"
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

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # 检查是否有函数统计
    local row_count
    row_count=$(echo "$result" | grep -c '^|' 2>/dev/null | head -1 || echo 0)

    if [[ $row_count -le 2 ]]; then
        pgtool_info "当前没有函数调用统计信息"
        return 0
    fi

    pgtool_info "函数调用统计信息:"
    echo ""
    echo "$result"
}

pgtool_stat_functions_help() {
    cat <<EOF
查看函数调用统计

显示用户定义的函数调用统计信息，包括：
- 模式名、函数名
- 调用次数
- 总执行时间(ms)
- 平均执行时间(ms)

数据来自 pg_stat_user_functions 视图。

用法: pgtool stat functions [选项]

选项:
  -h, --help       显示帮助
  -l, --limit N    限制显示行数

示例:
  pgtool stat functions
  pgtool stat functions --limit=10
  pgtool stat functions --format=json

注意:
  需要启用 track_functions 参数才能收集函数统计信息。
  如果所有计数为0，请检查 PostgreSQL 配置中的 track_functions 设置。
EOF
}
