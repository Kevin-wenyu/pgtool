#!/bin/bash
# commands/maintenance/vacuum.sh - VACUUM操作

pgtool_maintenance_vacuum() {
    local table=""
    local dry_run=false
    local full=false
    local analyze=false
    local threshold=10

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_maintenance_vacuum_help
                return 0
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
            --full)
                full=true
                shift
                ;;
            --analyze)
                analyze=true
                shift
                ;;
            --threshold)
                shift
                threshold="$1"
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

    pgtool_info "检查需要VACUUM的表..."
    echo ""

    # 测试连接
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 查找SQL文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "maintenance" "vacuum"); then
        pgtool_fatal "SQL文件未找到: maintenance/vacuum"
    fi

    # 执行SQL查询
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT:-table}")

    result=$(sed "s/:threshold/${threshold}/g" "$sql_file" | timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # 如果不是dry-run，执行vacuum
    if [[ "$dry_run" == false ]]; then
        echo ""
        if [[ -n "$table" ]]; then
            pgtool_info "执行VACUUM on $table..."
            local vacuum_cmd="VACUUM"
            [[ "$full" == true ]] && vacuum_cmd="VACUUM FULL"
            [[ "$analyze" == true ]] && vacuum_cmd="${vacuum_cmd} ANALYZE"

            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "$vacuum_cmd $table" 2>&1; then
                pgtool_info "VACUUM完成: $table"
            else
                pgtool_error "VACUUM失败: $table"
                return $EXIT_SQL_ERROR
            fi
        fi
    fi

    return $EXIT_SUCCESS
}

pgtool_maintenance_vacuum_help() {
    cat << 'EOF'
执行VACUUM操作清理死亡元组

用法: pgtool maintenance vacuum [选项]

选项:
  -h, --help              显示帮助
      --table=<name>      指定表名（默认显示所有需要vacuum的表）
      --dry-run           仅显示需要vacuum的表，不执行操作
      --full              执行VACUUM FULL（需要排他锁）
      --analyze           VACUUM后执行ANALYZE
      --threshold=<n>     死亡元组阈值（千行，默认10）

说明:
  VACUUM回收死亡元组占用的存储空间，防止表膨胀。
  VACUUM FULL完全重写表，需要排他锁，时间更长。

示例:
  # 查看需要vacuum的表
  pgtool maintenance vacuum --dry-run

  # vacuum指定表
  pgtool maintenance vacuum --table=users

  # vacuum并更新统计信息
  pgtool maintenance vacuum --table=users --analyze

  # 使用更低阈值（5千死亡元组）
  pgtool maintenance vacuum --threshold=5
EOF
}
