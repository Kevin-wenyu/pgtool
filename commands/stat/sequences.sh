#!/bin/bash
# commands/stat/sequences.sh - 查看序列统计

pgtool_stat_sequences() {
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_sequences_help
                return $EXIT_SUCCESS
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
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "stat" "sequences"); then
        pgtool_fatal "SQL文件未找到: stat/sequences"
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

    pgtool_info "序列统计信息:"
    echo ""
    echo "$result"

    return $EXIT_SUCCESS
}

pgtool_stat_sequences_help() {
    cat <<EOF
查看序列统计信息

显示所有用户序列的统计信息，包括：
- 模式名 (Schema)
- 序列名 (Sequence Name)
- 数据类型 (Type)
- 当前值 (Current Value)
- 起始值 (Start Value)
- 最小值 (Min Value)
- 最大值 (Max Value)
- 增量 (Increment)

用法: pgtool stat sequences [选项]

选项:
  -h, --help       显示帮助
  --format TYPE    输出格式 (table, csv, json)

示例:
  pgtool stat sequences
  pgtool stat sequences --format=csv
EOF
}
