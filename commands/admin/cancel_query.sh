#!/bin/bash
# commands/admin/cancel_query.sh - 取消查询

pgtool_admin_cancel_query() {
    local force=0
    local target_pid=""
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_admin_cancel_query_help
                return 0
                ;;
            --force)
                force=1
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --pid)
                shift
                target_pid="$1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$target_pid" ]]; then
        pgtool_error "必须指定 --pid 参数"
        pgtool_admin_cancel_query_help
        return $EXIT_INVALID_ARGS
    fi

    if ! is_int "$target_pid"; then
        pgtool_error "PID 必须是整数"
        return $EXIT_INVALID_ARGS
    fi

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 权限检查：需要超级用户或 pg_signal_backend 角色
    if ! pgtool_pg_is_superuser && ! pgtool_pg_has_role "pg_signal_backend"; then
        pgtool_error "权限不足: 需要超级用户或 pg_signal_backend 角色才能取消查询"
        pgtool_info "当前用户: $PGTOOL_USER"
        return $EXIT_PERMISSION
    fi

    # 查询进程信息
    local query_info
    query_info=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        -c "SELECT pid, usename, datname, state, query FROM pg_stat_activity WHERE pid = $target_pid" \
        --pset=format=aligned \
        --pset=border=2 \
        2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_error "无法查询进程信息"
        return $EXIT_SQL_ERROR
    fi

    if ! echo "$query_info" | grep -q "^| *$target_pid "; then
        pgtool_error "PID $target_pid 不存在或无法访问"
        return 1
    fi

    pgtool_warn "将要取消的查询:"
    echo ""
    echo "$query_info"

    # 试运行模式
    if [[ "$dry_run" -eq 1 ]]; then
        pgtool_info "试运行模式: 将要取消以下查询 (PID: $target_pid)"
        return 0
    fi

    if [[ "$force" -eq 0 ]]; then
        echo ""
        if ! confirm "确定要取消 PID $target_pid 的查询吗"; then
            pgtool_info "操作已取消"
            return 0
        fi
    fi

    pgtool_audit_admin "cancel-query" "--pid=$target_pid"

    pgtool_info "正在取消 PID $target_pid 的查询..."
    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        -c "SELECT pg_cancel_backend($target_pid)" \
        -t -A 2>&1)

    if [[ $? -eq 0 ]]; then
        if [[ "$result" == "t" ]] || [[ "$result" == "true" ]]; then
            pgtool_success "PID $target_pid 的查询已取消"
            return 0
        else
            pgtool_warn "PID $target_pid 可能不在活跃状态"
            return 1
        fi
    else
        pgtool_error "取消查询失败: $result"
        return 1
    fi
}

pgtool_admin_cancel_query_help() {
    cat <<EOF
取消正在执行的查询

取消指定 PID 的活跃查询。
与 kill-blocking 不同，cancel 只是取消当前查询，不会终止连接。

用法: pgtool admin cancel-query --pid=N [选项]

选项:
  -h, --help        显示帮助
      --force       跳过确认提示
      --dry-run     试运行模式：只显示将要取消的查询，不实际执行
      --pid N       要取消的进程 PID (必需)

示例:
  pgtool admin cancel-query --pid=12345
  pgtool admin cancel-query --pid=12345 --force
  pgtool admin cancel-query --pid=12345 --dry-run

与 kill-blocking 的区别:
  - cancel-query: 只取消当前查询，连接保持
  - kill-blocking: 终止整个连接

⚠️ 警告:
  取消查询可能导致事务回滚！
EOF
}
