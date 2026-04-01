#!/bin/bash
# commands/check/replication.sh - 检查流复制状态

pgtool_check_replication() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_replication_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "replication"); then
        pgtool_fatal "SQL文件未找到: check/replication"
    fi

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 检查是否是主库
    local is_primary
    is_primary=$(timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" \
        -c "SELECT pg_is_in_recovery()" -t -A 2>/dev/null | head -1)

    if [[ "$is_primary" == "t" ]]; then
        pgtool_warn "当前是备库 (standby)，显示的是接收信息"
        echo ""
    fi

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --pset=pager=off \
        --pset=format=aligned \
        --pset=border=2 \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    local row_count
    row_count=$(echo "$result" | grep -c '^|' 2>/dev/null | head -1 || echo 0)

    if [[ "$is_primary" == "f" && $row_count -le 2 ]]; then
        pgtool_warn "当前是主库，但没有活动的复制连接"
        return 0
    fi

    echo "$result"

    # 检查延迟
    if echo "$result" | grep -qE '[0-9]+s.*[0-9]+s' 2>/dev/null; then
        local max_lag
        max_lag=$(echo "$result" | grep -oE '[0-9]+s' | sed 's/s//' | sort -n | tail -1)
        if [[ "$max_lag" -gt 300 ]]; then
            pgtool_warn "复制延迟超过 5 分钟!"
            return 1
        fi
    fi
}

pgtool_check_replication_help() {
    cat <<EOF
检查流复制状态

显示流复制的连接状态和延迟信息：
- 客户端地址
- 复制状态 (streaming/startup/...)
- LSN (Log Sequence Number) 位置
- 各种延迟 (写延迟、刷盘延迟、重放延迟)

用法: pgtool check replication [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool check replication
EOF
}
