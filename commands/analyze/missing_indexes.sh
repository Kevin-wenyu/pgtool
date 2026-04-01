#!/bin/bash
# commands/analyze/missing_indexes.sh - 查找可能的缺失索引

pgtool_analyze_missing_indexes() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_analyze_missing_indexes_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "analyze" "missing_indexes"); then
        pgtool_fatal "SQL文件未找到: analyze/missing_indexes"
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
    row_count=$(echo "$result" | grep -E '^\|' 2>/dev/null | grep -v 'Table' | wc -l 2>/dev/null || echo 0)
    row_count=$(echo "$row_count" | head -1 | tr -d '[:space:]')

    if [[ "$row_count" -eq 0 ]]; then
        pgtool_success "没有发现明显的缺失索引"
        return 0
    fi

    pgtool_info "索引分析结果:"
    echo ""
    echo "$result"

    # 检查缺失索引
    local missing
    missing=$(echo "$result" | grep 'MISSING INDEX' 2>/dev/null | wc -l | head -1 || echo 0)
    missing=$(echo "$missing" | tr -d '[:space:]')

    if [[ "$missing" -gt 0 ]]; then
        echo ""
        pgtool_warn "发现 $missing 个表可能缺少索引"
        pgtool_info "建议为这些表的相关列创建索引"
    fi

    return 1
}

pgtool_analyze_missing_indexes_help() {
    cat <<EOF
查找可能的缺失索引

分析表的顺序扫描比例，识别可能需要索引的表：
- 显示表的扫描统计
- 顺序扫描 vs 索引扫描比例
- 给出索引建议

用法: pgtool analyze missing-indexes [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool analyze missing-indexes

注意:
  此分析基于 pg_stat_user_tables 的累积数据。
  建议定期执行 'SELECT pg_stat_reset()' 重置统计后重新分析。
EOF
}
