#!/bin/bash
# commands/stat/table.sh - 查看表级统计

pgtool_stat_table() {
    local schema=""
    local table=""

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
            --table)
                shift
                table="$1"
                shift
                ;;
            --schema=*)
                schema="${1#*=}"
                shift
                ;;
            --table=*)
                table="${1#*=}"
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

    # 如果有 schema 或 table 过滤，修改 SQL
    local sql_content
    sql_content=$(cat "$sql_file")

    # 添加 table 过滤条件（必须在 schema 替换之前）
    if [[ -n "$table" && -n "$schema" ]]; then
        # 同时指定了 schema 和 table，替换整个 WHERE 子句
        sql_content=$(awk -v s="$schema" -v t="$table" 'NR==30 {$0="WHERE schemaname = \047"s"\047 AND relname = \047"t"\047 AND schemaname NOT IN (\047pg_catalog\047, \047information_schema\047)"} 1' <<< "$sql_content")
    elif [[ -n "$table" ]]; then
        # 只指定了 table，在第 30 行添加表名过滤
        sql_content=$(awk -v t="$table" 'NR==30 {$0=$0" AND relname = \047"t"\047"} 1' <<< "$sql_content")
    elif [[ -n "$schema" ]]; then
        # 只指定了 schema，替换 WHERE 子句
        sql_content=$(awk -v s="$schema" 'NR==30 {$0="WHERE schemaname = \047"s"\047 AND schemaname NOT IN (\047pg_catalog\047, \047information_schema\047)"} 1' <<< "$sql_content")
    fi

    local result
    if [[ -n "$schema" || -n "$table" ]]; then
        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --pset=pager=off \
            --pset=format=aligned \
            --pset=border=2 \
            2>&1 <<< "$sql_content")
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

    # 检查是否有数据行（row_count > 2 表示有表头、分隔线和至少一行数据）
    # 实际上表头和数据行都以 | 开头，分隔线以 + 开头
    # 所以如果只有 2 行以 | 开头，表示只有表头和一行数据，这是正常的
    if [[ $row_count -lt 2 ]]; then
        if [[ -n "$table" ]]; then
            pgtool_info "没有找到表: ${schema:+$schema.}$table"
        else
            pgtool_info "没有找到用户表"
        fi
        return 0
    fi

    pgtool_info "表级统计:"
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
      --table NAME    指定表名（支持单独使用或与 --schema 组合）

示例:
  pgtool stat table
  pgtool stat table --schema=public
  pgtool stat table --table=users
  pgtool stat table --schema=public --table=users
EOF
}
