#!/bin/bash
# commands/admin/checkpoint.sh - 触发检查点

pgtool_admin_checkpoint() {
    local force=0
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_admin_checkpoint_help
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
            *)
                shift
                ;;
        esac
    done

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 权限检查：CHECKPOINT 需要超级用户
    if ! pgtool_pg_is_superuser; then
        pgtool_error "权限不足: CHECKPOINT 命令需要超级用户权限"
        pgtool_info "当前用户: $PGTOOL_USER"
        return $EXIT_PERMISSION
    fi

    # 获取检查点统计（兼容不同版本）
    local stats
    stats=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        -c "SELECT COUNT(*) FROM pg_stat_bgwriter" \
        -t -A 2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_warn "无法获取检查点统计"
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        pgtool_info "试运行模式: 将执行 CHECKPOINT 命令"
        pgtool_info "当前检查点统计:"
        echo "  定时检查点: $(echo "$stats" | cut -d'|' -f1 2>/dev/null || echo "N/A")"
        echo "  请求检查点: $(echo "$stats" | cut -d'|' -f2 2>/dev/null || echo "N/A")"
        return 0
    fi

    if [[ "$force" -eq 0 ]]; then
        if ! confirm "确定要立即触发检查点吗"; then
            pgtool_info "操作已取消"
            return 0
        fi
    fi

    pgtool_audit_admin "checkpoint" "manual-trigger"

    pgtool_info "正在触发检查点..."
    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        -c "CHECKPOINT" \
        2>&1)

    if [[ $? -eq 0 ]]; then
        pgtool_success "检查点已触发"

        # 再次获取统计
        local new_stats
        new_stats=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            -c "SELECT checkpoints_timed, checkpoints_req FROM pg_stat_bgwriter" \
            -t -A 2>&1)

        echo ""
        echo "新的检查点统计:"
        echo "  定时检查点: $(echo "$new_stats" | cut -d'|' -f1)"
        echo "  请求检查点: $(echo "$new_stats" | cut -d'|' -f2)"
        return 0
    else
        pgtool_error "触发检查点失败: $result"
        return 1
    fi
}

pgtool_admin_checkpoint_help() {
    cat <<EOF
触发检查点 (CHECKPOINT)

立即触发 PostgreSQL 检查点，强制将内存中的脏页写入磁盘。

用法: pgtool admin checkpoint [选项]

选项:
  -h, --help     显示帮助
      --force    跳过确认提示
      --dry-run  试运行模式：显示将要执行的操作，不实际执行

示例:
  pgtool admin checkpoint
  pgtool admin checkpoint --force
  pgtool admin checkpoint --dry-run

说明:
  检查点会将共享缓冲区中的脏页刷新到磁盘，
  并写入 WAL 记录以标记检查点位置。
  这可以用于在维护操作前确保数据持久化。

⚠️ 注意:
  频繁手动触发检查点可能影响性能！
EOF
}
