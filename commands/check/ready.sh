#!/bin/bash
# commands/check/ready.sh - 检查数据库就绪状态

# 默认是否接受备库
PGTOOL_CHECK_READY_ACCEPT_STANDBY="${PGTOOL_CHECK_READY_ACCEPT_STANDBY:-0}"

pgtool_check_ready() {
    local -a opts=()
    local accept_standby="$PGTOOL_CHECK_READY_ACCEPT_STANDBY"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_ready_help
                return 0
                ;;
            --accept-standby)
                accept_standby=1
                shift
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "检查数据库就绪状态..."
    echo ""

    # 测试连接（静默）
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        pgtool_error "数据库连接失败 - 未就绪"
        return $EXIT_CONNECTION_ERROR
    fi

    # 查找SQL文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "ready"); then
        pgtool_fatal "SQL文件未找到: check/ready"
    fi

    # 替换参数
    local sql_content
    sql_content=$(sed "s/:accept_standby/${accept_standby}/g" "$sql_file")

    # 执行SQL
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(echo "$sql_content" | timeout "$PGTOOL_TIMEOUT" psql \
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

    # 检查状态
    local status
    status=$(echo "$result" | grep -E "^\\s*(READY|STANDBY|NOT_READY)" | head -1 | tr -d ' ')

    if [[ "$status" == "READY" ]]; then
        pgtool_info "数据库就绪 - 正常运行"
        return $EXIT_SUCCESS
    elif [[ "$status" == "STANDBY" ]]; then
        pgtool_warn "数据库处于恢复模式（备库）"
        return $EXIT_GENERAL_ERROR
    else
        pgtool_error "数据库状态异常"
        return $EXIT_SQL_ERROR
    fi
}

pgtool_check_ready_help() {
    cat << 'EOF'
检查数据库是否就绪

检查数据库是否可接受连接并正常运行。

用法: pgtool check ready [选项]

选项:
  -h, --help           显示帮助
      --accept-standby 接受备库为就绪状态

返回值:
  0 - 数据库就绪（正常运行）
  1 - 数据库是备库（仅当未使用--accept-standby）
  3 - 连接失败

示例:
  pgtool check ready
  pgtool check ready --accept-standby

用途:
  - 健康检查端点（如Kubernetes livenessProbe）
  - 部署前验证数据库状态
  - CI/CD管道中确认数据库可用
EOF
}
