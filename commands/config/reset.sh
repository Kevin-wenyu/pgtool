#!/bin/bash
# commands/config/reset.sh - 生成 ALTER SYSTEM RESET 重置命令

#==============================================================================
# 主函数
#==============================================================================

pgtool_config_reset() {
    local param=""
    local all=false
    local apply=false
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_reset_help
                return 0
                ;;
            --param)
                shift
                param="$1"
                shift
                ;;
            --all)
                all=true
                shift
                ;;
            --apply)
                apply=true
                shift
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            -*)
                pgtool_error "未知选项: $1"
                pgtool_info "使用 'pgtool config reset --help' 查看帮助"
                return $EXIT_INVALID_ARGS
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # 处理位置参数格式: pgtool config reset shared_buffers
    if [[ ${#args[@]} -gt 0 ]] && [[ -z "$param" ]]; then
        param="${args[0]}"
    fi

    # 验证参数: --all 和 --param 必须指定一个，但不能同时指定
    if [[ "$all" == true ]] && [[ -n "$param" ]]; then
        pgtool_error "不能同时使用 --all 和 --param"
        pgtool_info "使用 --all 重置所有参数，或使用 --param 重置单个参数"
        return $EXIT_INVALID_ARGS
    fi

    if [[ "$all" == false ]] && [[ -z "$param" ]]; then
        pgtool_error "缺少参数名，请使用 --param 或 --all"
        pgtool_info "使用 'pgtool config reset --help' 查看帮助"
        return $EXIT_INVALID_ARGS
    fi

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    local sql=""
    local -a changed_params=()

    if [[ "$all" == true ]]; then
        # 获取所有非默认值的参数
        local changed_list
        changed_list=$(pgtool_pg_exec "SELECT name FROM pg_settings WHERE source != 'default' AND source != 'override' ORDER BY name" --tuples-only --quiet 2>/dev/null)

        if [[ -z "$changed_list" ]]; then
            pgtool_info "没有找到已修改的参数"
            return $EXIT_SUCCESS
        fi

        # 转换为数组
        while IFS= read -r line; do
            line=$(echo "$line" | tr -d ' ')
            if [[ -n "$line" ]]; then
                changed_params+=("$line")
            fi
        done <<< "$changed_list"

        pgtool_info "发现 ${#changed_params[@]} 个已修改的参数"
        echo ""

        sql="ALTER SYSTEM RESET ALL;"
    else
        # 检查参数是否存在
        local exists
        exists=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_settings WHERE name = '$param'")
        if [[ "$exists" == "0" ]]; then
            pgtool_error "参数不存在: $param"
            return $EXIT_NOT_FOUND
        fi

        # 获取当前值和来源
        local current
        local source
        local context
        current=$(pgtool_pg_query_one "SELECT setting FROM pg_settings WHERE name = '$param'")
        source=$(pgtool_pg_query_one "SELECT source FROM pg_settings WHERE name = '$param'")
        context=$(pgtool_pg_query_one "SELECT context FROM pg_settings WHERE name = '$param'")

        pgtool_info "参数: $param"
        pgtool_info "当前值: $current"
        pgtool_info "来源: $source"
        echo ""

        # 警告如果参数已经是默认值
        if [[ "$source" == "default" ]]; then
            pgtool_warn "参数 '$param' 已经是默认值"
        fi

        sql="ALTER SYSTEM RESET $param;"
    fi

    if [[ "$apply" == true ]]; then
        pgtool_info "执行 ALTER SYSTEM RESET..."
        if ! pgtool_pg_exec "$sql"; then
            pgtool_error "执行失败"
            return $EXIT_SQL_ERROR
        fi
        pgtool_info "重置完成"
        echo ""

        if [[ "$all" == true ]]; then
            echo "已重置所有 ALTER SYSTEM 修改的参数"
            echo "这些参数将恢复到 postgresql.conf 或编译默认值"
        else
            echo "参数 '$param' 已重置"
            echo "将恢复到: $(pgtool_pg_query_one "SELECT boot_val FROM pg_settings WHERE name = '$param'")"
        fi

        echo ""
        echo "提示: 需要执行 'pg_reload_conf()' 或重启 PostgreSQL 使配置生效"

        if [[ "$all" == false ]]; then
            local context
            context=$(pgtool_pg_query_one "SELECT context FROM pg_settings WHERE name = '$param'")
            if [[ "$context" == "postmaster" ]]; then
                echo "注意: 此参数需要重启 PostgreSQL 才能生效"
            elif [[ "$context" == "sighup" ]]; then
                echo "注意: 此参数可以通过 'pg_reload_conf()' 或 'pg_ctl reload' 重新加载"
            fi
        fi
    else
        echo "SQL: $sql"
        echo ""
        pgtool_info "干跑模式 (dry-run)，未实际执行"
        echo "添加 --apply 选项执行重置"

        if [[ "$all" == false ]]; then
            echo ""
            echo "提示: 需要执行 'pg_reload_conf()' 或重启 PostgreSQL 使配置生效"
            local context
            context=$(pgtool_pg_query_one "SELECT context FROM pg_settings WHERE name = '$param'")
            if [[ "$context" == "postmaster" ]]; then
                echo "注意: 此参数需要重启 PostgreSQL 才能生效"
            elif [[ "$context" == "sighup" ]]; then
                echo "注意: 此参数可以通过 'pg_reload_conf()' 或 'pg_ctl reload' 重新加载"
            fi
        fi
    fi

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_config_reset_help() {
    cat <<EOF
生成 ALTER SYSTEM RESET 重置命令

重置通过 ALTER SYSTEM 修改的参数值，恢复为默认值。

用法:
  pgtool config reset <参数名> [选项]
  pgtool config reset --param <参数名> [选项]
  pgtool config reset --all [选项]

选项:
  -h, --help          显示帮助
      --param NAME    要重置的参数名
      --all           重置所有已修改的参数
      --apply         实际执行（默认是干跑模式）

参数格式:
  支持两种方式:
    1. pgtool config reset shared_buffers
    2. pgtool config reset --param shared_buffers

执行模式:
  默认是干跑模式，只显示将要执行的 SQL 命令
  使用 --apply 选项实际执行 ALTER SYSTEM RESET

示例:
  # 干跑模式（只显示 SQL）
  pgtool config reset shared_buffers
  pgtool config reset --param work_mem
  pgtool config reset --all

  # 实际执行
  pgtool config reset shared_buffers --apply
  pgtool config reset --param max_connections --apply
  pgtool config reset --all --apply

注意:
  - ALTER SYSTEM RESET 修改的是 postgresql.auto.conf
  - 重置后需要重载配置或重启才能生效
  - context=postmaster 的参数需要重启
  - context=sighup 的参数可以通过 pg_reload_conf() 重载
EOF
}
