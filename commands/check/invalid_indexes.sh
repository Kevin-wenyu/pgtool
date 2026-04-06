#!/bin/bash
# commands/check/invalid_indexes.sh - 检查无效索引

pgtool_check_invalid_indexes() {
    local -a opts=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_invalid_indexes_help
                return 0
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
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

    pgtool_info "检查无效索引..."
    echo ""

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "invalid_indexes"); then
        pgtool_fatal "SQL文件未找到: check/invalid_indexes"
    fi

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
        pgtool_error "SQL执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # 检查是否有无效索引
    local count
    count=$(echo "$result" | grep -c "INVALID" || echo "0")
    count=$(echo "$count" | tr -d '\n')

    if [[ $count -gt 0 ]]; then
        pgtool_warn "发现 ${count} 个无效索引"
        pgtool_info "使用 'pgtool maintenance reindex --index=<name>' 重建索引"
        return 1
    fi

    pgtool_info "未发现无效索引"
    return $EXIT_SUCCESS
}

pgtool_check_invalid_indexes_help() {
    cat << 'EOF'
检查无效索引

查找因失败操作（如失败的CREATE INDEX CONCURRENTLY）导致的无效索引。
无效索引占用空间但不参与查询优化。

用法: pgtool check invalid-indexes [选项]

选项:
  -h, --help       显示帮助

说明:
  无效索引通常在以下情况产生:
  - CREATE INDEX CONCURRENTLY被中断
  - REINDEX CONCURRENTLY失败
  - 其他索引操作异常终止

返回值:
  0 - 无无效索引
  1 - 发现无效索引

示例:
  pgtool check invalid-indexes

修复:
  pgtool maintenance reindex --index=idx_name
EOF
}
