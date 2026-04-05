#!/bin/bash
# commands/config/set.sh - 生成 ALTER SYSTEM 设置命令

#==============================================================================
# 主函数
#==============================================================================

pgtool_config_set() {
    local param=""
    local value=""
    local apply=false
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_set_help
                return 0
                ;;
            --param)
                shift
                param="$1"
                shift
                ;;
            --value)
                shift
                value="$1"
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
                pgtool_info "使用 'pgtool config set --help' 查看帮助"
                return $EXIT_INVALID_ARGS
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # 处理位置参数格式: pgtool config set shared_buffers=4GB
    if [[ ${#args[@]} -gt 0 ]]; then
        local param_value="${args[0]}"
        if [[ "$param_value" =~ ^([^=]+)=(.*)$ ]]; then
            param="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            pgtool_error "参数格式错误，请使用: param=value 或 --param param --value value"
            return $EXIT_INVALID_ARGS
        fi
    fi

    # 验证必需参数
    if [[ -z "$param" ]]; then
        pgtool_error "缺少参数名，请使用 --param 或 param=value 格式"
        pgtool_info "使用 'pgtool config set --help' 查看帮助"
        return $EXIT_INVALID_ARGS
    fi

    if [[ -z "$value" ]]; then
        pgtool_error "缺少参数值，请使用 --value 或 param=value 格式"
        return $EXIT_INVALID_ARGS
    fi

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 检查参数是否存在
    local exists
    exists=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_settings WHERE name = '$param'")
    if [[ "$exists" == "0" ]]; then
        pgtool_error "参数不存在: $param"
        return $EXIT_NOT_FOUND
    fi

    # 获取当前值和上下文
    local current
    local context
    local vartype
    current=$(pgtool_pg_query_one "SELECT setting FROM pg_settings WHERE name = '$param'")
    context=$(pgtool_pg_query_one "SELECT context FROM pg_settings WHERE name = '$param'")
    vartype=$(pgtool_pg_query_one "SELECT vartype FROM pg_settings WHERE name = '$param'")

    pgtool_info "参数: $param"
    pgtool_info "类型: $vartype"
    pgtool_info "上下文: $context"
    echo ""

    # 验证值类型
    local validated_value="$value"
    case "$vartype" in
        bool)
            case "$value" in
                on|true|yes|1)
                    validated_value="on"
                    ;;
                off|false|no|0)
                    validated_value="off"
                    ;;
                *)
                    pgtool_warn "布尔值应该是: on/off, true/false, yes/no, 1/0"
                    ;;
            esac
            ;;
        integer)
            if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
                pgtool_error "参数 '$param' 需要整数值"
                return $EXIT_INVALID_ARGS
            fi
            ;;
        real)
            if ! [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
                pgtool_warn "参数 '$param' 应该是数值"
            fi
            ;;
        enum)
            local enum_values
            enum_values=$(pgtool_pg_query_one "SELECT enumvals::text FROM pg_settings WHERE name = '$param'")
            pgtool_info "可选值: $enum_values"
            ;;
    esac

    echo "当前值: $current"
    echo "新值:   $validated_value"
    echo ""

    # 生成 ALTER SYSTEM 命令
    local sql="ALTER SYSTEM SET $param = '$validated_value';"

    if [[ "$apply" == true ]]; then
        pgtool_info "执行 ALTER SYSTEM..."
        if ! pgtool_pg_exec "$sql"; then
            pgtool_error "执行失败"
            return $EXIT_SQL_ERROR
        fi
        pgtool_info "设置已更新"
        echo ""
        echo "提示: 需要执行 'pg_reload_conf()' 或重启 PostgreSQL 使配置生效"
        if [[ "$context" == "postmaster" ]]; then
            echo "注意: 此参数需要重启 PostgreSQL 才能生效"
        elif [[ "$context" == "sighup" ]]; then
            echo "注意: 此参数可以通过 'pg_reload_conf()' 或 'pg_ctl reload' 重新加载"
        fi
    else
        echo "SQL: $sql"
        echo ""
        pgtool_info "干跑模式 (dry-run)，未实际执行"
        echo "添加 --apply 选项执行设置"
        echo ""
        echo "提示: 需要执行 'pg_reload_conf()' 或重启 PostgreSQL 使配置生效"
        if [[ "$context" == "postmaster" ]]; then
            echo "注意: 此参数需要重启 PostgreSQL 才能生效"
        elif [[ "$context" == "sighup" ]]; then
            echo "注意: 此参数可以通过 'pg_reload_conf()' 或 'pg_ctl reload' 重新加载"
        fi
    fi

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_config_set_help() {
    cat <<EOF
生成 ALTER SYSTEM 设置命令

用法:
  pgtool config set <参数名>=<值> [选项]
  pgtool config set --param <参数名> --value <值> [选项]

选项:
  -h, --help          显示帮助
      --param NAME    参数名
      --value VALUE   参数值
      --apply         实际执行（默认是干跑模式）

参数格式:
  支持两种格式:
    1. pgtool config set shared_buffers=4GB
    2. pgtool config set --param shared_buffers --value 4GB

支持的类型验证:
  - bool:     on/off, true/false, yes/no, 1/0
  - integer:  整数
  - real:     浮点数
  - enum:     枚举值

执行模式:
  默认是干跑模式，只显示将要执行的 SQL 命令
  使用 --apply 选项实际执行 ALTER SYSTEM

示例:
  # 干跑模式（只显示 SQL）
  pgtool config set shared_buffers=4GB
  pgtool config set --param max_connections --value 200

  # 实际执行
  pgtool config set shared_buffers=4GB --apply
  pgtool config set --param work_mem --value 256MB --apply

注意:
  - ALTER SYSTEM 修改的是 postgresql.auto.conf
  - 修改后需要重载配置或重启才能生效
  - context=postmaster 的参数需要重启
  - context=sighup 的参数可以通过 pg_reload_conf() 重载
EOF
}
