#!/bin/bash
# commands/user/info.sh - 显示用户详细信息

#==============================================================================
# 主函数
#==============================================================================

pgtool_user_info() {
    local -a opts=()
    local -a args=()
    local role=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_info_help
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

    # 验证角色名
    if [[ -z "$role" ]]; then
        pgtool_error "请指定用户名"
        pgtool_info "用法: pgtool user info <用户名>"
        return $EXIT_INVALID_ARGS
    fi

    pgtool_info "查询用户详情: $role"
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "user" "info"); then
        pgtool_fatal "SQL文件未找到: user/info"
    fi

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 检查用户是否存在
    local exists
    exists=$(pgtool_pg_query_one "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = '$role')")
    if [[ "$exists" != "t" ]]; then
        pgtool_error "用户不存在: $role"
        return $EXIT_NOT_FOUND
    fi

    # 执行 SQL
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --variable="username=$role" \
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

    # 检查用户是否可以登录，显示连接信息
    local can_login
    can_login=$(pgtool_pg_query_one "SELECT rolcanlogin FROM pg_roles WHERE rolname = '$role'")
    if [[ "$can_login" == "t" ]]; then
        echo ""
        echo "--- 连接统计 ---"
        local conn_count
        conn_count=$(pgtool_pg_query_one "SELECT count(*) FROM pg_stat_activity WHERE usename = '$role'")
        echo "当前连接数: ${conn_count:-0}"
    fi

    return $EXIT_SUCCESS
}

#==============================================================================
# 帮助函数
#==============================================================================

pgtool_user_info_help() {
    cat <<EOF
显示用户详细信息

显示指定数据库用户的详细信息，包括：
- 基本角色属性（超级用户、继承、创建权限等）
- 连接和认证设置
- 组成员关系
- 当前连接数（如果可以登录）

用法: pgtool user info <用户名> [选项]
   或: pgtool user info --role=<用户名> [选项]

选项:
  -h, --help          显示帮助
      --role ROLE     指定用户名（与位置参数等效）
      --format FORMAT 输出格式 (table|json|csv|tsv)

输出字段:
  User            用户名
  Superuser       是否为超级用户 (t/f)
  Inherit         是否继承所属角色的权限 (t/f)
  Create Role     是否可以创建角色 (t/f)
  Create DB       是否可以创建数据库 (t/f)
  Can Login       是否可以登录 (t/f)
  Conn Limit      最大连接数 (-1 表示无限制)
  Password Expires 密码过期时间
  Replication     是否具有复制权限 (t/f)
  Bypass RLS      是否绕过行级安全策略 (t/f)
  Member Of       所属的角色组
  Has Members     包含的成员角色

示例:
  pgtool user info postgres
  pgtool user info myuser --format=json
  pgtool user info --role=admin
EOF
}
