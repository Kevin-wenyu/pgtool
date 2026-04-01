#!/bin/bash
# commands/stat/table.sh - 查看表级统计

pgtool_stat_table() {
    local schema=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_table_help
                return 0
                ;;
            --schema)
                shift
                schema="$1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "stat" "table"); then
        pgtool_fatal "SQL文件未找到: stat/table"
    fi

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 如果有 schema 过滤，修改 SQL
    local sql_content
    if [[ -n "$schema" ]]; then
        sql_content=$(cat "$sql_file")
        sql_content="${sql_content//WHERE schemaname NOT IN/WHERE schemaname = '$schema' AND schemaname NOT IN}"
    fi

    local result
    if [[ -n "$schema" ]]; then
        result=$(echo "$sql_content" | timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --pset=pager=off \
            --pset=format=aligned \
            --pset=border=2 \
            2>&1)
    else
        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            --pset=pager=off \
            --pset=format=aligned \
            --pset=border=2 \
            2>&1)
    fi

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    local row_count
    row_count=$(echo "$result" | grep -c '^|' 2>/dev/null | head -1 || echo 0)

    if [[ $row_count -le 2 ]]; then
        pgtool_info "没有找到用户表"
        return 0
    fi

    pgtool_info "表级统计 (Top 20 by size):"
    echo ""
    echo "$result"

    # 检查死元组比例
    local high_dead_ratio
    high_dead_ratio=$(echo "$result" | awk -F'|' '/^[[:space:]]*\|/ { if ($13+0 > 20) print $2 }' | head -5)
    if [[ -n "$high_dead_ratio" ]]; then
        echo ""
        pgtool_warn "以下表死元组比例超过 20%:"
        echo "$high_dead_ratio"
    fi
}

pgtool_stat_table_help() {
    cat <<EOF
查看表级统计

显示用户表的详细统计信息：
- 表名和大小（含索引）
- 顺序扫描/索引扫描次数
- 元组操作统计
- 活/死元组数量
- 死元组比例
- 最后 vacuum/analyze 时间

用法: pgtool stat table [选项]

选项:
  -h, --help          显示帮助
      --schema NAME   指定 schema

示例:
  pgtool stat table
  pgtool stat table --schema=public
EOF
}
