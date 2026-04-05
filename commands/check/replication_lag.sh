#!/bin/bash
# commands/check/replication_lag.sh - 检查复制延迟

#==============================================================================
# 默认阈值
#==============================================================================

PGTOOL_REPLICATION_LAG_WARNING="${PGTOOL_REPLICATION_LAG_WARNING:-1048576}"    # 1MB
PGTOOL_REPLICATION_LAG_CRITICAL="${PGTOOL_REPLICATION_LAG_CRITICAL:-10485760}" # 10MB

#==============================================================================
# 主函数
#==============================================================================

pgtool_check_replication_lag() {
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_replication_lag_help
                return 0
                ;;
            --threshold-warning)
                shift
                PGTOOL_REPLICATION_LAG_WARNING="$1"
                shift
                ;;
            --threshold-critical)
                shift
                PGTOOL_REPLICATION_LAG_CRITICAL="$1"
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

    pgtool_info "检查复制延迟..."
    pgtool_info "警告阈值: $(numfmt --to=iec ${PGTOOL_REPLICATION_LAG_WARNING} 2>/dev/null || echo ${PGTOOL_REPLICATION_LAG_WARNING})"
    pgtool_info "危险阈值: $(numfmt --to=iec ${PGTOOL_REPLICATION_LAG_CRITICAL} 2>/dev/null || echo ${PGTOOL_REPLICATION_LAG_CRITICAL})"
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "replication_lag"); then
        pgtool_fatal "SQL文件未找到: check/replication_lag"
    fi

    # 测试连接（静默）
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
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

    # 检查是否为空（无复制）
    if [[ -z "$(echo "$result" | grep -v "^-" | grep -v "^(" | grep -v "^[[:space:]]*$")" ]]; then
        pgtool_warn "当前数据库未配置流复制或不是主库"
        return $EXIT_SUCCESS
    fi

    # 显示结果
    echo "$result"

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_check_replication_lag_help() {
    cat <<EOF
检查复制延迟

监控主从流复制的延迟情况，包括字节延迟和连接状态。
在主库上执行，显示所有连接的从库延迟。
在从库上执行，当前版本暂不支持。

推荐阈值（字节）：
  - 警告: 1MB (1048576)
  - 危险: 10MB (10485760)

注意：
  - 需要在主库上执行
  - 需要具有 pg_monitor 角色或 superuser 权限
  - 字节延迟是近似值，实际延迟还取决于网络和应用

用法: pgtool check replication-lag [选项]

选项:
  -h, --help              显示帮助
      --threshold-warning NUM   警告阈值，单位字节 (默认: 1048576 = 1MB)
      --threshold-critical NUM  危险阈值，单位字节 (默认: 10485760 = 10MB)

环境变量:
  PGTOOL_REPLICATION_LAG_WARNING   警告阈值
  PGTOOL_REPLICATION_LAG_CRITICAL  危险阈值

输出列说明:
  Standby      - 从库 IP 地址
  State        - 复制状态 (streaming, startup 等)
  Lag(bytes)   - 延迟字节数
  Connected    - 连接时长
  Sync Mode    - 同步模式 (async, sync, potential)

示例:
  pgtool check replication-lag
  pgtool check replication-lag --threshold-warning=524288 --threshold-critical=2097152
EOF
}
