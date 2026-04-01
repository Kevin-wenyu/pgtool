#!/bin/bash
# commands/analyze/slow_queries.sh - 分析慢查询

pgtool_analyze_slow_queries() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_analyze_slow_queries_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "analyze" "slow_queries"); then
        pgtool_fatal "SQL文件未找到: analyze/slow_queries"
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

    # 检查是否安装了 pg_stat_statements
    if echo "$result" | grep -q "not installed"; then
        pgtool_warn "pg_stat_statements 扩展未安装"
        echo ""
        echo "要启用慢查询分析，请执行:"
        echo "  CREATE EXTENSION pg_stat_statements;"
        echo ""
        echo "并在 postgresql.conf 中添加:"
        echo "  shared_preload_libraries = 'pg_stat_statements'"
        return 1
    fi

    local row_count=0
    row_count=$(echo "$result" | grep -E '^\|' 2>/dev/null | grep -v 'Query' | wc -l 2>/dev/null || echo 0)
    row_count=$(echo "$row_count" | head -1 | tr -d '[:space:]')

    if [[ "$row_count" -eq 0 ]]; then
        pgtool_info "暂无慢查询数据"
        return 0
    fi

    pgtool_info "慢查询分析 (Top 10 by mean time):"
    echo ""
    echo "$result"

    return 0
}

pgtool_analyze_slow_queries_help() {
    cat <<EOF
分析慢查询

显示执行时间最长的查询统计（需要 pg_stat_statements 扩展）：
- 查询文本（截断）
- 执行次数
- 总执行时间
- 平均/最大执行时间
- 返回行数
- 缓存命中率

用法: pgtool analyze slow-queries [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool analyze slow-queries

前提条件:
  需要安装 pg_stat_statements 扩展:
  CREATE EXTENSION pg_stat_statements;

  并在 postgresql.conf 中配置:
  shared_preload_libraries = 'pg_stat_statements'
EOF
}
