#!/bin/bash
# commands/maintenance/analyze.sh - ANALYZE操作

pgtool_maintenance_analyze() {
    local table=""
    local schema=""
    local dry_run=false
    local hours=24

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_maintenance_analyze_help
                return 0
                ;;
            --table)
                shift
                table="$1"
                shift
                ;;
            --schema)
                shift
                schema="$1"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --hours)
                shift
                hours="$1"
                shift
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            -*)
                pgtool_error "未知选项: $1"
                return $EXIT_INVALID_ARGS
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "检查统计信息状态..."
    echo ""

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "maintenance" "analyze"); then
        pgtool_fatal "SQL文件未找到: maintenance/analyze"
    fi

    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT:-table}")

    result=$(sed "s/:hours/${hours}/g" "$sql_file" | timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # 执行analyze
    if [[ "$dry_run" == false ]]; then
        echo ""
        if [[ -n "$table" ]]; then
            pgtool_info "执行ANALYZE: $table"
            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "ANALYZE $table" 2>&1; then
                pgtool_info "ANALYZE完成: $table"
            else
                pgtool_error "ANALYZE失败: $table"
                return $EXIT_SQL_ERROR
            fi
        elif [[ -n "$schema" ]]; then
            pgtool_info "执行ANALYZE: schema $schema"
            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "ANALYZE $schema" 2>&1; then
                pgtool_info "Schema ANALYZE完成: $schema"
            else
                pgtool_error "Schema ANALYZE失败: $schema"
                return $EXIT_SQL_ERROR
            fi
        fi
    fi

    return $EXIT_SUCCESS
}

pgtool_maintenance_analyze_help() {
    cat << 'EOF'
更新表统计信息

用法: pgtool maintenance analyze [选项]

选项:
  -h, --help              显示帮助
      --table=<name>      指定表名
      --schema=<name>     指定模式名
      --dry-run           仅显示统计信息状态，不执行操作
      --hours=<n>         统计信息过期小时数（默认24）

说明:
  ANALYZE更新表的统计信息，帮助优化器生成更好的执行计划。
  建议在大量数据加载或批量更新后执行。

示例:
  # 查看统计信息状态
  pgtool maintenance analyze --dry-run

  # analyze指定表
  pgtool maintenance analyze --table=users

  # analyze整个schema
  pgtool maintenance analyze --schema=public

  # 查看超过48小时未analyze的表
  pgtool maintenance analyze --hours=48 --dry-run
EOF
}
