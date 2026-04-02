#!/bin/bash
# commands/user/permissions.sh - 显示用户权限

#==============================================================================
# 主函数
#==============================================================================

pgtool_user_permissions() {
    local -a opts=()
    local -a args=()
    local role=""
    local limit=50

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_permissions_help
                return 0
                ;;
            --role)
                shift
                role="$1"
                shift
                ;;
            --limit)
                shift
                limit="$1"
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
        pgtool_info "用法: pgtool user permissions <用户名>"
        return $EXIT_INVALID_ARGS
    fi

    # 验证 limit 是正整数
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
        pgtool_error "--limit 必须是正整数"
        return $EXIT_INVALID_ARGS
    fi

    pgtool_info "查询用户权限: $role"
    echo ""

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

    # 查找 SQL 文件
    local db_sql
    local table_sql
    if ! db_sql=$(pgtool_pg_find_sql "user" "permissions_database"); then
        pgtool_fatal "SQL文件未找到: user/permissions_database"
    fi
    if ! table_sql=$(pgtool_pg_find_sql "user" "permissions_tables"); then
        pgtool_fatal "SQL文件未找到: user/permissions_tables"
    fi

    # 数据库权限
    pgtool_info "数据库权限:"
    echo ""

    local db_result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    db_result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$db_sql" \
        --variable="username=$role" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local db_exit_code=$?

    if [[ $db_exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $db_exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $db_result"
        return $EXIT_SQL_ERROR
    fi

    echo "$db_result"

    # 表权限
    echo ""
    pgtool_info "表权限 (限制: $limit 条):"
    echo ""

    local table_result
    table_result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$table_sql" \
        --variable="username=$role" \
        --variable="limit=$limit" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local table_exit_code=$?

    if [[ $table_exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $table_exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $table_result"
        return $EXIT_SQL_ERROR
    fi

    echo "$table_result"

    return $EXIT_SUCCESS
}

#==============================================================================
# 帮助函数
#==============================================================================

pgtool_user_permissions_help() {
    cat <<EOF
显示用户权限

显示指定用户在数据库和表级别的权限详情：
- 数据库级别: CONNECT, CREATE, TEMPORARY 权限
- 表级别: SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER 权限

用法: pgtool user permissions <用户名> [选项]
   或: pgtool user permissions --role=<用户名> [选项]

选项:
  -h, --help          显示帮助
      --role ROLE     指定用户名（与位置参数等效）
      --limit NUM     表权限显示数量限制 (默认: 50)
      --format FORMAT 输出格式 (table|json|csv|tsv)

数据库权限字段:
  Database    数据库名称
  Connect     是否有连接权限 (t/f)
  Create      是否有创建权限 (t/f)
  Temporary   是否有创建临时表权限 (t/f)

表权限字段:
  Schema      模式名称
  Table       表名称
  Select      是否有查询权限 (t/f)
  Insert      是否有插入权限 (t/f)
  Update      是否有更新权限 (t/f)
  Delete      是否有删除权限 (t/f)
  Truncate    是否有截断权限 (t/f)
  References  是否有外键引用权限 (t/f)
  Trigger     是否有创建触发器权限 (t/f)

示例:
  pgtool user permissions postgres
  pgtool user permissions myuser --limit=100
  pgtool user permissions --role=admin --format=json
EOF
}
