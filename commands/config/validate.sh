#!/bin/bash
# commands/config/validate.sh - 验证 PostgreSQL 配置参数

#==============================================================================
# 主函数
#==============================================================================

pgtool_config_validate() {
    local -a opts=()
    local -a args=()
    local strict_mode=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_validate_help
                return 0
                ;;
            --strict)
                strict_mode=true
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

    pgtool_info "验证 PostgreSQL 配置参数..."
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "config" "validate"); then
        pgtool_fatal "SQL文件未找到: config/validate"
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

    # 检查是否有警告或危险
    local has_warning=false
    local has_critical=false

    if echo "$result" | grep -q "WARNING"; then
        has_warning=true
    fi
    if echo "$result" | grep -q "CRITICAL"; then
        has_critical=true
    fi

    echo ""
    pgtool_info "验证完成"

    # 在严格模式下，如果有警告则返回非零
    if [[ "$strict_mode" == "true" ]] && { [[ "$has_warning" == "true" ]] || [[ "$has_critical" == "true" ]]; }; then
        return 1
    fi

    # 如果有严重问题，返回错误
    if [[ "$has_critical" == "true" ]]; then
        return 2
    fi

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_config_validate_help() {
    cat <<EOF
验证 PostgreSQL 配置参数

检查关键配置参数是否符合最佳实践建议，并返回验证状态。

用法: pgtool config validate [选项]

选项:
  -h, --help          显示帮助
      --strict        如果有警告则返回非零状态码

检查参数:
  max_connections     - 最大连接数 (建议: <= 100)
  shared_buffers      - 共享缓冲区 (建议: >= 128MB 或 25% RAM)
  work_mem            - 工作内存 (建议: 10MB - 64MB)
  autovacuum          - 自动清理 (建议: on)
  logging_collector   - 日志收集器 (建议: on)
  track_activities    - 活动跟踪 (建议: on)

状态说明:
  OK       - 配置符合建议值
  WARNING  - 配置需要关注，但非严重
  CRITICAL - 配置存在严重问题，需要立即修复

示例:
  pgtool config validate
  pgtool config validate --strict
  pgtool config validate --format=json
EOF
}
