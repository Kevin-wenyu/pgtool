#!/bin/bash
# commands/check/ssl.sh - 检查 SSL/TLS 配置

#==============================================================================
# 主函数
#==============================================================================

pgtool_check_ssl() {
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_ssl_help
                return 0
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "检查 SSL/TLS 配置..."
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "ssl"); then
        pgtool_fatal "SQL文件未找到: check/ssl"
    fi

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 执行 SQL
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
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

    # 检查是否有警告
    if echo "$result" | grep -q "WARNING"; then
        return 1
    fi

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_check_ssl_help() {
    cat <<EOF
检查 SSL/TLS 配置

检查 PostgreSQL 的 SSL/TLS 配置状态，包括 SSL 是否启用、
证书文件配置以及当前连接的 SSL 状态。

用法: pgtool check ssl [选项]

选项:
  -h, --help              显示帮助

输出:
  OK       - SSL 配置正常
  WARNING  - SSL 未启用或配置不完整

检查项:
  - SSL Enabled    - 服务器是否启用了 SSL
  - SSL证书文件   - 证书文件是否已配置
  - 连接SSL状态   - 当前连接是否使用 SSL

示例:
  pgtool check ssl
  pgtool check ssl --format=json
EOF
}
