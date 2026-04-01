#!/bin/bash
# commands/analyze/bloat.sh - 分析表膨胀

pgtool_analyze_bloat() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_analyze_bloat_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "analyze" "bloat"); then
        pgtool_fatal "SQL文件未找到: analyze/bloat"
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
        pgtool_success "没有发现明显的表膨胀"
        return 0
    fi

    pgtool_warn "发现 $row_count 个表可能存在膨胀:"
    echo ""
    echo "$result"

    # 检查高膨胀表
    local high_bloat
    high_bloat=$(echo "$result" | grep 'HIGH' 2>/dev/null | wc -l | head -1 || echo 0)
    high_bloat=$(echo "$high_bloat" | tr -d '[:space:]')

    if [[ "$high_bloat" -gt 0 ]]; then
        echo ""
        pgtool_warn "发现 $high_bloat 个高膨胀表 (HIGH)，建议执行 VACUUM"
    fi

    return 1
}

pgtool_analyze_bloat_help() {
    cat <<EOF
分析表和索引膨胀

检查表的死元组比例，识别需要 vacuum 的表：
- 显示表的总大小
- 活元组和死元组数量
- 死元组比例
- 膨胀等级 (OK/MEDIUM/HIGH)
- 最后 vacuum 时间

用法: pgtool analyze bloat [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool analyze bloat

建议:
  - 死元组比例超过 20% 的表建议执行 VACUUM
  - 可使用 'pgtool admin checkpoint' 触发检查点后执行
EOF
}
