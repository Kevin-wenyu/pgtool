#!/bin/bash
# commands/maintenance/reindex.sh - 重建索引

pgtool_maintenance_reindex() {
    local index=""
    local table=""
    local dry_run=false
    local concurrent=true
    local min_ratio=0.3

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_maintenance_reindex_help
                return 0
                ;;
            --index)
                shift
                index="$1"
                shift
                ;;
            --table)
                shift
                table="$1"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --no-concurrent)
                concurrent=false
                shift
                ;;
            --min-ratio)
                shift
                min_ratio="$1"
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

    pgtool_info "检查膨胀索引..."
    echo ""

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "maintenance" "reindex"); then
        pgtool_fatal "SQL文件未找到: maintenance/reindex"
    fi

    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT:-table}")

    result=$(sed "s/:min_ratio/${min_ratio}/g" "$sql_file" | timeout "$PGTOOL_TIMEOUT" psql \
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

    # 执行reindex
    if [[ "$dry_run" == false ]]; then
        echo ""
        local reindex_cmd="REINDEX"
        [[ "$concurrent" == true ]] && reindex_cmd="REINDEX INDEX CONCURRENTLY"

        if [[ -n "$index" ]]; then
            pgtool_info "重建索引: $index"
            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "$reindex_cmd $index" 2>&1; then
                pgtool_info "索引重建完成: $index"
            else
                pgtool_error "索引重建失败: $index"
                return $EXIT_SQL_ERROR
            fi
        elif [[ -n "$table" ]]; then
            pgtool_info "重建表的所有索引: $table"
            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "REINDEX TABLE CONCURRENTLY $table" 2>&1; then
                pgtool_info "表索引重建完成: $table"
            else
                pgtool_error "表索引重建失败: $table"
                return $EXIT_SQL_ERROR
            fi
        fi
    fi

    return $EXIT_SUCCESS
}

pgtool_maintenance_reindex_help() {
    cat << 'EOF'
重建索引消除膨胀

用法: pgtool maintenance reindex [选项]

选项:
  -h, --help              显示帮助
      --index=<name>      指定索引名
      --table=<name>      指定表名（重建该表所有索引）
      --dry-run           仅显示膨胀索引，不执行操作
      --no-concurrent     不使用CONCURRENTLY（需要锁）
      --min-ratio=<n>     最小膨胀比例（默认0.3）

说明:
  REINDEX重建索引，消除因更新删除导致的索引膨胀。
  默认使用CONCURRENTLY选项，不阻塞读写。

示例:
  # 查看膨胀索引
  pgtool maintenance reindex --dry-run

  # 重建指定索引
  pgtool maintenance reindex --index=idx_users_email

  # 重建表的所有索引
  pgtool maintenance reindex --table=users
EOF
}
