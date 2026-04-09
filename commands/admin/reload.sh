#!/bin/bash
# commands/admin/reload.sh - 重载配置

pgtool_admin_reload() {
    local force=0
    local dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_admin_reload_help
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

    # 权限检查：pg_reload_conf 需要超级用户
    if ! pgtool_pg_is_superuser; then
        pgtool_error "权限不足: 配置重载需要超级用户权限"
        pgtool_info "当前用户: $PGTOOL_USER"
        return $EXIT_PERMISSION
    fi

    # 显示一些可重载的配置参数
    local reloadable
    reloadable=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        -c "SELECT name, setting FROM pg_settings WHERE context = 'sighup' ORDER BY name LIMIT 10" \
        --pset=format=aligned \
        --pset=border=2 \
        -t 2>&1)

    pgtool_info "部分可重载参数 (context='sighup'):"
    echo "$reloadable"
    echo "..."
    echo ""

    # 试运行模式
    if [[ "$dry_run" -eq 1 ]]; then
        pgtool_info "试运行模式: 配置文件将被重载"
        return 0
    fi

    if [[ "$force" -eq 0 ]]; then
        if ! confirm "确定要重载配置文件吗"; then
            pgtool_info "操作已取消"
            return 0
        fi
    fi

    pgtool_audit_admin "reload" "config-reload"

    pgtool_info "正在重载配置..."
    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        -c "SELECT pg_reload_conf()" \
        -t -A 2>&1)

    if [[ $? -eq 0 ]]; then
        if [[ "$result" == "t" ]] || [[ "$result" == "true" ]]; then
            pgtool_success "配置已重载"

            # 显示重载后的参数值
            echo ""
            pgtool_info "一些常用参数当前值:"
            timeout "$PGTOOL_TIMEOUT" psql \
                "${PGTOOL_CONN_OPTS[@]}" \
                -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('max_connections', 'shared_buffers', 'work_mem', 'maintenance_work_mem')" \
                --pset=format=aligned \
                --pset=border=2 \
                -t

            return 0
        else
            pgtool_error "配置重载失败"
            return 1
        fi
    else
        pgtool_error "配置重载失败: $result"
        return 1
    fi
}

pgtool_admin_reload_help() {
    cat <<EOF
重载配置文件 (pg_reload_conf)

重载 PostgreSQL 配置文件 (postgresql.conf)，
 应用 context='sighup' 的参数修改，无需重启。

用法: pgtool admin reload [选项]

选项:
  -h, --help     显示帮助
      --force    跳过确认提示
      --dry-run  试运行模式：只显示将要重载的配置，不实际执行

示例:
  pgtool admin reload
  pgtool admin reload --force
  pgtool admin reload --dry-run

可重载的参数包括:
  - max_connections
  - shared_buffers (部分情况)
  - work_mem
  - maintenance_work_mem
  - 以及其他 context='sighup' 的参数

需要重启的参数:
  - 修改端口 (port)
  - 修改数据目录相关参数
  - 以及其他 context='postmaster' 的参数
EOF
}
