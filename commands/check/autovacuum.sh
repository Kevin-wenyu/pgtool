#!/bin/bash
# commands/check/autovacuum.sh - 检查 autovacuum 状态

pgtool_check_autovacuum() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_autovacuum_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "autovacuum"); then
        pgtool_fatal "SQL文件未找到: check/autovacuum"
    fi

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --pset=pager=off \
        --pset=format=aligned \
        --pset=border=2 \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    pgtool_info "Autovacuum 状态摘要:"
    echo ""
    echo "$result"

    # 检查是否需要警告
    local needs_vacuum
    needs_vacuum=$(echo "$result" | grep 'Tables Needing Vacuum' | awk -F'|' '{print $2}' | tr -d ' ')
    if [[ "$needs_vacuum" -gt 0 ]] 2>/dev/null; then
        pgtool_warn "有 $needs_vacuum 个表需要 vacuum"
        return 1
    fi

    return 0
}

pgtool_check_autovacuum_help() {
    cat <<EOF
检查 autovacuum 状态

显示 autovacuum 的统计信息：
- 正在运行的 autovacuum 进程数
- 需要 vacuum 的表数量
- 超过 24 小时未 vacuum 的表

用法: pgtool check autovacuum [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool check autovacuum
EOF
}
