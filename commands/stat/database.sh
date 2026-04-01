#!/bin/bash
# commands/stat/database.sh - 查看数据库级统计

pgtool_stat_database() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_stat_database_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "stat" "database"); then
        pgtool_fatal "SQL文件未找到: stat/database"
    fi

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
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

    pgtool_info "数据库统计信息:"
    echo ""
    echo "$result"
}

pgtool_stat_database_help() {
    cat <<EOF
查看数据库级统计

显示所有可连接数据库的统计信息：
- 数据库大小
- 当前连接数
- 事务提交/回滚数
- 回滚率
- 块读取/命中数
- 缓存命中率
- 元组操作统计
- 冲突和死锁数
- 临时文件统计

用法: pgtool stat database [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool stat database
EOF
}
