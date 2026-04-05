#!/bin/bash
# commands/config/get.sh - 获取 PostgreSQL 配置参数值

#==============================================================================
# 主函数
#==============================================================================

pgtool_config_get() {
    local -a opts=()
    local -a args=()
    local param=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_get_help
                return 0
                ;;
            --param)
                shift
                param="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # 如果没有使用 --param，尝试从位置参数获取
    if [[ -z "$param" ]] && [[ ${#args[@]} -gt 0 ]]; then
        param="${args[0]}"
    fi

    # 验证参数
    if [[ -z "$param" ]]; then
        pgtool_error "缺少参数名"
        pgtool_info "用法: pgtool config get <参数名>"
        pgtool_info "      pgtool config get --param=<参数名>"
        return $EXIT_INVALID_ARGS
    fi

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "config" "get"); then
        pgtool_fatal "SQL文件未找到: config/get"
    fi

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 验证参数是否存在
    local exists
    exists=$(pgtool_pg_query_one "SELECT 1 FROM pg_settings WHERE name = '$param'")
    if [[ -z "$exists" ]]; then
        pgtool_error "参数不存在: $param"
        return $EXIT_NOT_FOUND
    fi

    # 执行 SQL 查询
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --variable="name='$param'" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # 显示结果
    echo "$result"

    # 获取 context 并显示生效提示
    local context
    context=$(pgtool_pg_query_one "SELECT context FROM pg_settings WHERE name = '$param'")

    echo ""
    echo "生效方式:"
    case "$context" in
        postmaster)
            echo "  需要重启 PostgreSQL 服务才能生效"
            ;;
        sighup)
            echo "  需要执行 SELECT pg_reload_conf() 或重启 PostgreSQL 服务"
            ;;
        superuser|superuser-backend)
            echo "  即时生效 (需要超级用户权限)"
            ;;
        user)
            echo "  即时生效 (可在会话级别设置)"
            ;;
        *)
            echo "  即时生效"
            ;;
    esac

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_config_get_help() {
    cat <<EOF
获取 PostgreSQL 配置参数值

显示指定配置参数的当前值、单位、上下文、类型、默认值等详细信息，
并提示参数修改后的生效方式。

用法: pgtool config get <参数名> [选项]
       pgtool config get --param=<参数名> [选项]

选项:
  -h, --help              显示帮助

输出字段:
  name        - 参数名称
  setting     - 当前值
  unit        - 单位 (如 MB, ms 等)
  context     - 修改上下文 (postmaster, sighup, superuser, user)
  vartype     - 值类型 (bool, integer, real, string, enum)
  default     - 启动默认值
  source      - 值来源
  category    - 参数类别
  short_desc  - 简短描述
  extra_desc  - 详细描述

生效方式说明:
  postmaster      - 需要重启 PostgreSQL 服务
  sighup          - 需要执行 pg_reload_conf() 或重启
  superuser       - 即时生效 (需要超级用户权限)
  user            - 即时生效 (可在会话级别设置)

示例:
  pgtool config get shared_buffers
  pgtool config get --param=max_connections
  pgtool config get work_mem --format=json
EOF
}
