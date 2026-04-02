#!/bin/bash
# commands/user/list.sh - 列出数据库用户

#==============================================================================
# 主函数
#==============================================================================

pgtool_user_list() {
    local -a opts=()
    local -a args=()
    local with_superuser=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_list_help
                return 0
                ;;
            --with-superuser)
                with_superuser=true
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

    pgtool_info "列出数据库用户..."
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "user" "list"); then
        pgtool_fatal "SQL文件未找到: user/list"
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

    # 显示统计信息
    local total_count
    local superuser_count

    # 提取总行数 (排除表头行和分隔行)
    total_count=$(echo "$result" | grep -v '^+' | grep -v '^ *User' | grep -v '^ *$' | wc -l | tr -d ' ')

    # 统计超级用户数量
    if [[ "$PGTOOL_FORMAT" == "json" ]]; then
        # JSON格式需要不同方式统计
        superuser_count=$(echo "$result" | grep -o '"Superuser": "t"' | wc -l | tr -d ' ')
    else
        # 表格格式：查找 Superuser 列为 t 的行
        superuser_count=$(echo "$result" | awk -F'|' '/^\|/ && $2 ~ /t/ {count++} END {print count}')
    fi

    # 确保数字有效
    total_count=${total_count:-0}
    superuser_count=${superuser_count:-0}

    echo ""
    echo "--- 统计信息 ---"
    echo "总用户数: $total_count"
    if [[ "$with_superuser" == "true" ]]; then
        echo "超级用户: $superuser_count"
    fi

    return $EXIT_SUCCESS
}

#==============================================================================
# 帮助函数
#==============================================================================

pgtool_user_list_help() {
    cat <<EOF
列出数据库用户

显示所有非系统数据库用户及其角色属性，包括：
- 用户名
- 超级用户权限
- 创建数据库权限
- 创建角色权限
- 登录权限
- 连接数限制
- 密码过期时间
- 所属角色组

用法: pgtool user list [选项]

选项:
  -h, --help          显示帮助
      --with-superuser    显示超级用户统计信息
      --format FORMAT     输出格式 (table|json|csv|tsv)

输出字段:
  User            用户名
  Superuser       是否为超级用户 (t/f)
  Create DB       是否可以创建数据库 (t/f)
  Create Role     是否可以创建角色 (t/f)
  Can Login       是否可以登录 (t/f)
  Conn Limit      最大连接数 (-1 表示无限制)
  Password Expires 密码过期时间
  Member Of       所属角色组

示例:
  pgtool user list
  pgtool user list --with-superuser
  pgtool user list --format=json
EOF
}
