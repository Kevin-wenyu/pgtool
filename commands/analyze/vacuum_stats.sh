#!/bin/bash
# commands/analyze/vacuum_stats.sh - 查看 vacuum 统计信息

pgtool_analyze_vacuum_stats() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_analyze_vacuum_stats_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "analyze" "vacuum_stats"); then
        pgtool_fatal "SQL文件未找到: analyze/vacuum_stats"
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

    pgtool_info "Vacuum 统计信息:"
    echo ""
    echo "$result"

    # 检查长时间未 vacuum 的表
    local old_vacuum
    old_vacuum=$(echo "$result" | grep -E '^\|' | grep -v 'Table' | \
        awk -F'|' '$4 > 10000 {print $2}' 2>/dev/null | head -5)

    if [[ -n "$old_vacuum" ]]; then
        echo ""
        pgtool_warn "以下表死元组超过 10000，建议执行 VACUUM:"
        echo "$old_vacuum"
    fi

    return 0
}

pgtool_analyze_vacuum_stats_help() {
    cat <<EOF
查看 Vacuum 统计信息

显示表的 vacuum 和 analyze 统计：
- 活/死元组数量
- 死元组比例
- 最后 vacuum/analyze 时间
- vacuum/analyze 执行次数

用法: pgtool analyze vacuum-stats [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool analyze vacuum-stats

相关命令:
  pgtool check autovacuum    # 检查 autovacuum 状态
  pgtool analyze bloat       # 分析表膨胀
EOF
}
