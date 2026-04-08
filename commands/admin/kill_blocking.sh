#!/bin/bash
# commands/admin/kill_blocking.sh - 终止阻塞会话

pgtool_admin_kill_blocking() {
    local force=0
    local target_pid=""
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_admin_kill_blocking_help
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

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 权限检查：需要超级用户或 pg_signal_backend 角色
    if ! pgtool_pg_is_superuser && ! pgtool_pg_has_role "pg_signal_backend"; then
        pgtool_error "权限不足: 需要超级用户或 pg_signal_backend 角色才能终止会话"
        pgtool_info "当前用户: $PGTOOL_USER"
        return $EXIT_PERMISSION
    fi

    # 查找阻塞进程
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "admin" "kill_blocking"); then
        pgtool_fatal "SQL文件未找到: admin/kill_blocking"
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

    local row_count=0
    row_count=$(echo "$result" | grep -E '^\|' | grep -v 'pid' | wc -l 2>/dev/null || echo 0)
    row_count=$(echo "$row_count" | head -1 | tr -d '[:space:]')

    if [[ "$row_count" -eq 0 ]]; then
        pgtool_success "没有发现阻塞会话"
        return 0
    fi

    pgtool_warn "发现 $row_count 个阻塞会话:"
    echo ""
    echo "$result"

    # 试运行模式
    if [[ "$dry_run" -eq 1 ]]; then
        pgtool_info "试运行模式: 以下会话将被终止:"
        echo "$result" | grep -E '^\|' | grep -v 'pid' | awk -F'|' '{print "  - PID:" $2 " 用户:" $3 " 数据库:" $4}'
        return 0
    fi

    # 如果指定了 PID，只终止那个
    if [[ -n "$target_pid" ]]; then
        if ! echo "$result" | grep -q "^| *$target_pid "; then
            pgtool_error "PID $target_pid 不在阻塞会话列表中"
            return 1
        fi

        if [[ "$force" -eq 0 ]]; then
            echo ""
            if ! confirm "确定要终止 PID $target_pid 吗"; then
                pgtool_info "操作已取消"
                return 0
            fi
        fi

        pgtool_audit_admin "kill-blocking" "--pid=$target_pid"

        pgtool_info "正在终止 PID $target_pid..."
        local cancel_result
        cancel_result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            -c "SELECT pg_terminate_backend($target_pid)" \
            -t -A 2>&1)

        if [[ $? -eq 0 ]]; then
            pgtool_success "PID $target_pid 已终止"
            return 0
        else
            pgtool_error "终止 PID $target_pid 失败: $cancel_result"
            return 1
        fi
    fi

    # 终止所有阻塞会话
    echo ""
    if [[ "$force" -eq 0 ]]; then
        if ! confirm "确定要终止上述所有阻塞会话吗"; then
            pgtool_info "操作已取消"
            return 0
        fi
    fi

    pgtool_audit_admin "kill-blocking" "bulk-termination-start"

    local killed=0
    local failed=0
    local pid
    for pid in $(echo "$result" | grep -E '^\|' | grep -v 'pid' | awk -F'|' '{print $2}' | tr -d ' '); do
        if timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            -c "SELECT pg_terminate_backend($pid)" \
            -t -A >/dev/null 2>&1; then
            ((killed++))
            pgtool_success "终止 PID $pid"
        else
            ((failed++))
            pgtool_error "终止 PID $pid 失败"
        fi
    done

    pgtool_audit_admin "kill-blocking" "bulk-termination-complete: $killed success, $failed failed"

    echo ""
    pgtool_info "终止完成: $killed 成功, $failed 失败"
}

pgtool_admin_kill_blocking_help() {
    cat <<EOF
终止阻塞其他会话的进程

查找并终止正在阻塞其他会话的进程。
可以终止所有阻塞进程，或指定特定 PID。

用法: pgtool admin kill-blocking [选项]

选项:
  -h, --help        显示帮助
      --force       跳过确认提示
      --dry-run     试运行模式：只显示将要终止的会话，不实际执行
      --pid N       只终止指定 PID

示例:
  pgtool admin kill-blocking          # 终止所有阻塞会话
  pgtool admin kill-blocking --force  # 不确认直接终止
  pgtool admin kill-blocking --dry-run # 试运行，只查看不终止
  pgtool admin kill-blocking --pid=12345

⚠️ 警告:
  终止会话可能导致事务回滚，请谨慎使用！
EOF
}
