#!/bin/bash
# commands/user/activity.sh - 显示用户活动统计

#==============================================================================
# 主函数
#==============================================================================

pgtool_user_activity() {
    local -a opts=()
    local -a args=()
    local role=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_activity_help
                return 0
                ;;
            --role)
                shift
                role="$1"
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
                opts+=("$1")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # 如果没有通过 --role 指定，使用第一个位置参数
    if [[ -z "$role" && ${#args[@]} -gt 0 ]]; then
        role="${args[0]}"
    fi

    pgtool_info "查询用户活动统计${role:+: $role}"
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "user" "activity"); then
        pgtool_fatal "SQL文件未找到: user/activity"
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
        --variable="username=${role:-NULL}" \
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

    # 显示总连接数
    echo ""
    local total
    total=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_stat_activity WHERE backend_type = 'client backend'")
    echo "总连接数: ${total:-0}"

    return $EXIT_SUCCESS
}

#==============================================================================
# 帮助函数
#==============================================================================

pgtool_user_activity_help() {
    cat <<EOF
显示用户活动统计

显示每个用户的连接活动统计，包括：
- Active: 活跃连接数
- Idle: 空闲连接数
- Idle in Tx: 空闲事务中的连接数
- Waiting: 等待中的连接数
- Total: 总连接数

用法: pgtool user activity [用户名] [选项]
   或: pgtool user activity --role=<用户名> [选项]

选项:
  -h, --help          显示帮助
      --role ROLE     指定用户名（与位置参数等效）
      --format FORMAT 输出格式 (table|json|csv|tsv)

输出字段:
  User            用户名
  Active          活跃连接数
  Idle            空闲连接数
  Idle in Tx      空闲事务中的连接数
  Waiting         等待中的连接数
  Total           总连接数

示例:
  pgtool user activity              # 显示所有用户的活动
  pgtool user activity myuser       # 显示指定用户的活动
  pgtool user activity --role=myuser --format=json
EOF
}
