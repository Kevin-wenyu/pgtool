#!/bin/bash
# commands/check/deadlocks.sh - 检查死锁

PGTOOL_CHECK_DEADLOCKS_THRESHOLD="${PGTOOL_CHECK_DEADLOCKS_THRESHOLD:-1}"

pgtool_check_deadlocks() {
    local -a opts=()
    local threshold="$PGTOOL_CHECK_DEADLOCKS_THRESHOLD"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_deadlocks_help
                return 0
                ;;
            --threshold)
                shift
                threshold="$1"
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

    pgtool_info "检查死锁统计..."
    pgtool_info "阈值: ${threshold} 次死锁"
    echo ""

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "deadlocks"); then
        pgtool_fatal "SQL文件未找到: check/deadlocks"
    fi

    local sql_content
    sql_content=$(sed "s/:threshold/${threshold}/g" "$sql_file")

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

    # 检查结果
    local warning_count
    warning_count=$(echo "$result" | grep -c "WARNING" || echo "0")

    if [[ $warning_count -gt 0 ]]; then
        pgtool_warn "检测到死锁活动！"
        return $EXIT_GENERAL_ERROR
    fi

    pgtool_info "未检测到死锁问题"
    return $EXIT_SUCCESS
}

pgtool_check_deadlocks_help() {
    cat << 'EOF'
检查数据库死锁情况

用法: pgtool check deadlocks [选项]

选项:
  -h, --help           显示帮助
      --threshold NUM  死锁警告阈值（默认: 1）

说明:
  检查自统计重置以来发生的死锁次数。
  死锁是事务相互等待导致的循环依赖，
  PostgreSQL会自动回滚其中一个事务，但频繁死锁影响性能。

返回值:
  0 - 死锁数在阈值范围内
  1 - 死锁数超过阈值

示例:
  pgtool check deadlocks
  pgtool check deadlocks --threshold=5

注意:
  统计在stats_reset后重置。查看统计重置时间：
  SELECT stats_reset FROM pg_stat_database WHERE datname = current_database();
EOF
}
