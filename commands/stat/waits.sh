#!/bin/bash
# commands/stat/waits.sh - 查看等待事件统计

#==============================================================================
# 主函数
#==============================================================================

pgtool_stat_waits() {
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_waits_help
                return 0
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

    pgtool_info "查看等待事件统计..."
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "stat" "waits"); then
        pgtool_fatal "SQL文件未找到: stat/waits"
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

    # 显示结果
    echo "$result"

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_stat_waits_help() {
    cat <<EOF
查看等待事件统计

显示当前数据库的等待事件分布情况，帮助诊断性能瓶颈。
等待事件分为两大类：
  - CPU/Running : 正在执行，占用CPU
  - Wait Events : 正在等待资源（IO、锁、网络等）

常见等待事件类型：
  - IO      : DataFileRead, WALWriteSync 等（磁盘IO）
  - Lock    : relation, tuple（锁等待）
  - Client  : ClientRead, ClientWrite（客户端网络）
  - Timeout : Sleep, VacuumDelay（主动等待）
  - Activity: 后台进程等待

用法: pgtool stat waits [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool stat waits
  pgtool stat waits --format=json

输出列说明:
  Wait Type    - 等待事件大类
  Wait Event   - 具体等待事件
  Sessions     - 当前等待的会话数
  Percentage   - 占总会话数的百分比
EOF
}
