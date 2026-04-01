#!/bin/bash
# commands/stat/locks.sh - 查看锁等待

pgtool_stat_locks() {
    local -a opts=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_locks_help
                return 0
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

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "stat" "locks"); then
        pgtool_fatal "SQL文件未找到: stat/locks"
    fi

    # 测试连接
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 执行 SQL
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
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # 检查是否有锁等待
    local row_count
    row_count=$(echo "$result" | grep -c '^|' 2>/dev/null | head -1 || echo 0)

    if [[ $row_count -le 2 ]]; then
        pgtool_success "当前没有锁等待"
        return 0
    fi

    pgtool_warn "发现锁等待:"
    echo ""
    echo "$result"

    return 1
}

pgtool_stat_locks_help() {
    cat <<EOF
查看锁等待情况

显示正在等待锁的会话以及阻塞它们的会话：
- 等待进程的 PID 和用户信息
- 阻塞进程的 PID 和用户信息
- 被锁定的对象
- 等待模式和等待时间
- 双方正在执行的查询

用法: pgtool stat locks [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool stat locks

相关命令:
  pgtool admin kill-blocking  # 终止阻塞会话
EOF
}
