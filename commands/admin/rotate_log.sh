#!/bin/bash
# commands/admin/rotate_log.sh - 轮换日志文件

pgtool_admin_rotate_log() {
    local force=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_admin_rotate_log_help
                return 0
                ;;
            --force)
                force=1
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    if [[ "$force" -eq 0 ]]; then
        if ! confirm "确定要立即轮换日志文件吗"; then
            pgtool_info "操作已取消"
            return 0
        fi
    fi

    pgtool_info "正在轮换日志文件..."

    local sql_file
    sql_file=$(pgtool_pg_find_sql "admin" "rotate_log")

    if [[ -z "$sql_file" ]]; then
        pgtool_error "找不到 SQL 文件: admin/rotate_log"
        return $EXIT_GENERAL_ERROR
    fi

    local result
    result=$(pgtool_exec_sql_file "$sql_file" "table" 2>&1)

    if [[ $? -eq 0 ]]; then
        pgtool_success "日志文件已轮换"
        echo ""
        echo "$result"
        return $EXIT_SUCCESS
    else
        pgtool_error "轮换日志文件失败: $result"
        return $EXIT_SQL_ERROR
    fi
}

pgtool_admin_rotate_log_help() {
    cat <<EOF
轮换日志文件 (pg_rotate_logfile)

立即轮换 PostgreSQL 日志文件，关闭当前日志文件并创建新的日志文件。

用法: pgtool admin rotate-log [选项]

选项:
  -h, --help     显示帮助
      --force    跳过确认提示

示例:
  pgtool admin rotate-log
  pgtool admin rotate-log --force

说明:
  此命令调用 pg_rotate_logfile() 函数来轮换日志文件。
  需要 PostgreSQL 配置为使用日志文件模式（logging_collector = on）。

⚠️ 注意:
  需要超级用户权限或 pg_signal_backend 角色。
EOF
}
