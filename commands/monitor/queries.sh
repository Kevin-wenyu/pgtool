#!/bin/bash
# commands/monitor/queries.sh - 实时监控活跃查询

# 主函数: pgtool_monitor_queries
pgtool_monitor_queries() {
    local interval=2
    local limit=20
    local once=false
    local help=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_monitor_queries_help
                return 0
                ;;
            -i|--interval)
                shift
                interval="$1"
                shift
                ;;
            -l|--limit)
                shift
                limit="$1"
                shift
                ;;
            --once)
                once=true
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                # 全局选项，跳过参数值
                shift
                shift
                ;;
            -*)
                pgtool_error "未知选项: $1"
                pgtool_monitor_queries_help
                return $EXIT_INVALID_ARGS
                ;;
            *)
                shift
                ;;
        esac
    done

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "monitor" "queries"); then
        pgtool_fatal "SQL文件未找到: monitor/queries"
    fi

    # 测试连接
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 替换 SQL 中的参数
    local sql
    sql=$(sed "s/:limit/${limit}/g" "$sql_file")

    # --once 模式：执行一次并退出
    if [[ "$once" == true ]]; then
        pgtool_monitor_queries_once "$sql"
        return $?
    fi

    # 交互模式：检查 TTY
    if [[ ! -t 1 ]]; then
        pgtool_error "交互模式需要终端 (TTY)"
        pgtool_info "使用 --once 选项在非终端环境中运行"
        return $EXIT_INVALID_ARGS
    fi

    # 运行交互模式
    pgtool_monitor_queries_interactive "$sql" "$interval" "$limit"
}

# 执行一次查询
pgtool_monitor_queries_once() {
    local sql="$1"
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --command="$sql" \
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

    echo "$result"
    return 0
}

# 交互模式：实时刷新
pgtool_monitor_queries_interactive() {
    local sql="$1"
    local interval="$2"
    local limit="$3"
    local running=true

    # 设置信号处理
    cleanup() {
        running=false
        pgtool_monitor_cleanup
    }
    trap cleanup EXIT INT TERM

    # 隐藏光标
    pgtool_monitor_hide_cursor

    # 清屏
    pgtool_monitor_clear_screen

    # 刷新循环
    while [[ "$running" == true ]]; do
        pgtool_monitor_clear_screen
        pgtool_monitor_print_header "Query Monitor (limit: $limit)" 80

        # 执行查询
        local result
        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --command="$sql" \
            --pset=format=unaligned \
            --pset=fieldsep='|' \
            --pset=border=0 \
            --pset=header \
            --pset=pager=off \
            --quiet \
            2>&1)

        local exit_code=$?

        if [[ $exit_code -eq 124 ]]; then
            echo "查询超时"
        elif [[ $exit_code -ne 0 ]]; then
            echo "查询失败: $result"
        else
            # 上色输出
            pgtool_monitor_queries_colorize "$result"
        fi

        # 提示信息
        printf "\n%b按 'q' 退出%b\n" "$PGTOOL_MONITOR_COLOR_YELLOW" "$PGTOOL_MONITOR_COLOR_RESET"

        # 读取按键（带超时）
        local key
        key=$(pgtool_monitor_read_key "$interval")

        # 检查是否退出
        if pgtool_monitor_is_quit_key "$key"; then
            break
        fi
    done

    # 清理（信号处理函数会执行）
    return 0
}

# 根据查询时间上色的输出
pgtool_monitor_queries_colorize() {
    local result="$1"
    local line_num=0

    # 读取每一行
    while IFS= read -r line; do
        ((line_num++))

        # 第一行是表头
        if [[ $line_num -eq 1 ]]; then
            printf "%b%s%b\n" "$PGTOOL_MONITOR_COLOR_BOLD" "$line" "$PGTOOL_MONITOR_COLOR_RESET"
            continue
        fi

        # 空行或分隔符跳过
        if [[ -z "$line" ]] || [[ "$line" == "("* ]]; then
            echo "$line"
            continue
        fi

        # 解析行数据，查找 query_time 列（第6列，索引从1开始）
        # 格式: pid|usename|datname|client_addr|state|query_time|query_text
        local query_time
        query_time=$(echo "$line" | cut -d'|' -f6)

        # 根据查询时间选择颜色
        local color
        color=$(pgtool_monitor_color_for_state "active" "$query_time")

        printf "%b%s%b\n" "$color" "$line" "$PGTOOL_MONITOR_COLOR_RESET"
    done <<< "$result"
}

# 帮助函数
pgtool_monitor_queries_help() {
    cat <<EOF
实时监控活跃查询

显示所有非空闲的后端进程，包括：
- PID, 用户名, 数据库
- 客户端地址
- 会话状态
- 查询执行时间（秒）
- 正在执行的 SQL 语句（前100字符）

用法: pgtool monitor queries [选项]

选项:
  -h, --help          显示帮助
  -i, --interval SEC  刷新间隔（秒，默认: 2）
  -l, --limit NUM     显示条目数限制（默认: 20）
  --once              只运行一次，不循环刷新
  --format FORMAT     输出格式 (table, json, csv)

交互模式:
  实时监控运行时，按 'q' 键退出

颜色说明:
  红色    > 60秒 长时间运行的查询
  黄色    > 10秒 中等时间运行的查询
  绿色    <= 10秒 正常查询

示例:
  pgtool monitor queries              # 交互模式，默认2秒刷新
  pgtool monitor queries -i 1 -l 10   # 1秒刷新，显示10条
  pgtool monitor queries --once       # 执行一次并退出
  pgtool monitor queries --once --format=json
EOF
}
