#!/bin/bash
# commands/analyze/index_usage.sh - 分析索引使用情况

pgtool_analyze_index_usage() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_analyze_index_usage_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "analyze" "index_usage"); then
        pgtool_fatal "SQL文件未找到: analyze/index_usage"
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

    local row_count=0
    row_count=$(echo "$result" | grep -E '^\|' 2>/dev/null | grep -v 'Schema' | wc -l 2>/dev/null || echo 0)
    row_count=$(echo "$row_count" | head -1 | tr -d '[:space:]')

    if [[ "$row_count" -eq 0 ]]; then
        pgtool_success "没有发现索引"
        return 0
    fi

    pgtool_info "找到 $row_count 个索引："
    echo ""
    echo "$result"

    # 检查未使用索引
    local unused_count
    unused_count=$(echo "$result" | grep 'UNUSED' 2>/dev/null | wc -l | head -1 || echo 0)
    unused_count=$(echo "$unused_count" | tr -d '[:space:]')

    if [[ "$unused_count" -gt 0 ]]; then
        echo ""
        pgtool_warn "发现 $unused_count 个未使用索引 (UNUSED)，建议评估是否可以删除"
    fi

    # 检查很少使用的索引
    local rarely_count
    rarely_count=$(echo "$result" | grep 'RARELY USED' 2>/dev/null | wc -l | head -1 || echo 0)
    rarely_count=$(echo "$rarely_count" | tr -d '[:space:]')

    if [[ "$rarely_count" -gt 0 ]]; then
        echo ""
        pgtool_warn "发现 $rarely_count 个很少使用的索引 (RARELY USED)"
    fi

    return 0
}

pgtool_analyze_index_usage_help() {
    cat <<EOF
分析索引使用情况

检查用户表的索引扫描统计，识别未使用或很少使用的索引：
- 显示索引所属的模式和表
- 索引扫描次数
- 索引大小
- 使用状态 (UNUSED/RARELY USED/ACTIVE)

用法: pgtool analyze index-usage [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool analyze index-usage

建议:
  - UNUSED 状态的索引可以被评估删除
  - RARELY USED 状态的索引需要关注
EOF
}
