#!/bin/bash
# commands/stat/indexes.sh - 查看索引使用情况

pgtool_stat_indexes() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_indexes_help
                return 0
                ;;
            --unused)
                PGTOOL_SHOW_UNUSED=1
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "stat" "index"); then
        pgtool_fatal "SQL文件未找到: stat/index"
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

    pgtool_info "索引统计 (Top 30 by size):"
    echo ""
    echo "$result"

    # 检查未使用的索引
    local unused_count
    unused_count=$(echo "$result" | grep -c 'UNUSED' 2>/dev/null | head -1 || echo 0)
    unused_count=$(echo "$unused_count" | tr -d ' ')

    if [[ "$unused_count" -gt 0 ]]; then
        echo ""
        pgtool_warn "发现 $unused_count 个未使用的索引 (UNUSED)"
        echo ""
        echo "$result" | grep -E '^\|' | grep 'UNUSED'
    fi

    # 检查低使用索引
    local low_count
    low_count=$(echo "$result" | grep -c 'LOW' 2>/dev/null | head -1 || echo 0)
    low_count=$(echo "$low_count" | tr -d ' ')

    if [[ "$low_count" -gt 0 ]]; then
        echo ""
        pgtool_warn "发现 $low_count 个低使用索引 (LOW)"
    fi
}

pgtool_stat_indexes_help() {
    cat <<EOF
查看索引使用情况

显示用户表索引的统计信息：
- 索引所属表和索引名
- 索引大小
- 索引扫描次数
- 读取的元组数
- 使用状态 (UNUSED/LOW/OK)

用法: pgtool stat indexes [选项]

选项:
  -h, --help     显示帮助
      --unused   只显示未使用的索引

示例:
  pgtool stat indexes
  pgtool stat indexes --unused

提示:
  UNUSED - 从未被使用的索引，可以考虑删除
  LOW    - 使用频率低的索引
  OK     - 正常使用的索引
EOF
}
