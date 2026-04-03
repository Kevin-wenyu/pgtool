#!/bin/bash
# commands/monitor/replication.sh - 实时监控复制延迟

# 主函数: pgtool_monitor_replication
pgtool_monitor_replication() {
    local interval=2
    local once=false
    local help=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_monitor_replication_help
                return 0
                ;;
            -i|--interval)
                shift
                interval="$1"
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
                pgtool_monitor_replication_help
                return $EXIT_INVALID_ARGS
                ;;
            *)
                shift
                ;;
        esac
    done

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "monitor" "replication"); then
        pgtool_fatal "SQL文件未找到: monitor/replication"
    fi

    # 测试连接
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 检查是否为主库
    local is_primary
    is_primary=$(pgtool_pg_query_one "SELECT EXISTS(SELECT 1 FROM pg_stat_replication)")
    if [[ "$is_primary" != "t" ]]; then
        pgtool_error "当前数据库不是主库或未配置流复制"
        return $EXIT_GENERAL_ERROR
    fi

    # --once 模式：执行一次并退出
    if [[ "$once" == true ]]; then
        pgtool_monitor_replication_once "$sql_file"
        return $?
    fi

    # 交互模式：检查 TTY
    if [[ ! -t 1 ]]; then
        pgtool_error "交互模式需要终端 (TTY)"
        pgtool_info "使用 --once 选项在非终端环境中运行"
        return $EXIT_INVALID_ARGS
    fi

    # 运行交互模式
    pgtool_monitor_replication_interactive "$sql_file" "$interval"
}

# 执行一次查询
pgtool_monitor_replication_once() {
    local sql_file="$1"
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    local result
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

    echo "$result"
    return 0
}

# 交互模式：实时刷新
pgtool_monitor_replication_interactive() {
    local sql_file="$1"
    local interval="$2"
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
        pgtool_monitor_print_header "Replication Monitor" 80

        # 执行查询
        local result
        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
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
            pgtool_monitor_replication_colorize "$result"
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

# 根据复制延迟上色的输出
pgtool_monitor_replication_colorize() {
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

        # 解析 lag_bytes 列（第5列，索引从1开始）
        # 格式: replica|state|sent_lsn|flush_lsn|lag_bytes|lag_size|reply_time
        local lag_bytes
        lag_bytes=$(echo "$line" | awk -F'|' '{print $5}' | tr -d ' ')

        # 根据延迟大小选择颜色
        # 红色: > 1GB, 黄色: > 100MB, 绿色: 其他
        if [[ "$lag_bytes" =~ ^[0-9]+$ ]]; then
            if [[ "$lag_bytes" -gt 1073741824 ]]; then
                echo -e "${PGTOOL_MONITOR_COLOR_RED}${line}${PGTOOL_MONITOR_COLOR_RESET}"
            elif [[ "$lag_bytes" -gt 104857600 ]]; then
                echo -e "${PGTOOL_MONITOR_COLOR_YELLOW}${line}${PGTOOL_MONITOR_COLOR_RESET}"
            else
                echo -e "${PGTOOL_MONITOR_COLOR_GREEN}${line}${PGTOOL_MONITOR_COLOR_RESET}"
            fi
        else
            # 非数字，使用默认颜色
            echo "$line"
        fi
    done <<< "$result"
}

# 帮助函数
pgtool_monitor_replication_help() {
    cat <<EOF
实时监控主从复制延迟

显示所有连接到主库的复制从库信息，包括：
- 从库地址 (replica)
- 复制状态 (state)
- 已发送 LSN (sent_lsn)
- 已刷新 LSN (flush_lsn)
- 延迟字节数 (lag_bytes)
- 延迟大小 (lag_size)
- 最后回复时间 (reply_time)

用法: pgtool monitor replication [选项]

选项:
  -h, --help          显示帮助
  -i, --interval SEC  刷新间隔（秒，默认: 2）
  --once              只运行一次，不循环刷新
  --format FORMAT     输出格式 (table, json, csv)

交互模式:
  实时监控运行时，按 'q' 键退出

颜色说明:
  红色    > 1GB   严重延迟
  黄色    > 100MB 警告延迟
  绿色    <= 100MB 正常延迟

示例:
  pgtool monitor replication              # 交互模式，默认2秒刷新
  pgtool monitor replication -i 5         # 5秒刷新间隔
  pgtool monitor replication --once       # 执行一次并退出
  pgtool monitor replication --once --format=json
EOF
}
