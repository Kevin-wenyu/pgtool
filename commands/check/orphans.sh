#!/bin/bash
# commands/check/orphans.sh

pgtool_check_orphans() {
    local -a opts=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_orphans_help
                return 0
                ;;
            --include-info)
                shift
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "检查孤儿对象..."
    echo ""

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "orphans"); then
        pgtool_fatal "SQL文件未找到: check/orphans"
    fi

    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
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
        pgtool_error "SQL 执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    if echo "$result" | grep -q "WARNING"; then
        return 1
    fi

    return $EXIT_SUCCESS
}

pgtool_check_orphans_help() {
    cat <<EOF
检查孤儿对象

检查临时表、孤立索引、空闲预提交事务等孤儿对象。

用法: pgtool check orphans [选项]

选项:
  -h, --help       显示帮助
  --include-info   包含INFO级别的问题

示例:
  pgtool check orphans
EOF
}
