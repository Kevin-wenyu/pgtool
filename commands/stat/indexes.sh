#!/bin/bash
# commands/stat/indexes.sh - 查看索引使用情况

pgtool_stat_indexes() {
    local schema=""
    local table=""

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
    if ! sql_file=$(pgtool_pg_find_sql "stat" "index"); then
        pgtool_fatal "SQL文件未找到: stat/index"
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
        sql_content=$(awk -v s="$schema" -v t="$table" 'NR==18 {$0="WHERE schemaname = \047"s"\047 AND relname = \047"t"\047 AND schemaname NOT IN (\047pg_catalog\047, \047information_schema\047)"} 1' <<< "$sql_content")
    elif [[ -n "$table" ]]; then
        # 只指定了 table，在第 18 行添加表名过滤
        sql_content=$(awk -v t="$table" 'NR==18 {$0=$0" AND relname = \047"t"\047"} 1' <<< "$sql_content")
    elif [[ -n "$schema" ]]; then
        # 只指定了 schema，替换 WHERE 子句
        sql_content=$(awk -v s="$schema" 'NR==18 {$0="WHERE schemaname = \047"s"\047 AND schemaname NOT IN (\047pg_catalog\047, \047information_schema\047)"} 1' <<< "$sql_content")
    fi

    local result
    if [[ -n "$schema" || -n "$table" ]]; then
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

    pgtool_info "索引统计:"
    echo ""
    echo "$result"

    # 检查未使用的索引
    local unused_count
    unused_count=$(echo "$result" | grep -c 'UNUSED' 2>/dev/null || echo 0)
    unused_count=$(echo "$unused_count" | head -1 | tr -d ' ')

    if [[ "$unused_count" -gt 0 ]]; then
        echo ""
        pgtool_warn "发现 $unused_count 个未使用的索引 (UNUSED)"
        echo ""
        echo "$result" | grep -E '^\|' | grep 'UNUSED'
    fi

    # 检查低使用索引
    local low_count
    low_count=$(echo "$result" | grep -c 'LOW' 2>/dev/null || echo 0)
    low_count=$(echo "$low_count" | head -1 | tr -d ' ')

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
      --schema NAME   指定 schema
      --table NAME    指定表名（支持单独使用或与 --schema 组合）

示例:
  pgtool stat indexes
  pgtool stat indexes --unused
  pgtool stat indexes --table=users
  pgtool stat indexes --schema=public --table=users

提示:
  UNUSED - 从未被使用的索引，可以考虑删除
  LOW    - 使用频率低的索引
  OK     - 正常使用的索引
EOF
}
