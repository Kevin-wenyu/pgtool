#!/bin/bash
# commands/check/tablespace.sh - 检查表空间使用情况

#==============================================================================
# 主函数
#==============================================================================

pgtool_check_tablespace() {
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_tablespace_help
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

    pgtool_info "检查表空间使用情况..."
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "tablespace"); then
        pgtool_fatal "SQL文件未找到: check/tablespace"
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
pgtool_check_tablespace_help() {
    cat <<EOF
检查表空间使用情况

显示所有表空间的大小和位置信息。
注意：此命令只显示 PostgreSQL 层面的表空间大小，
不包括文件系统层面的磁盘使用率和剩余空间。

用法: pgtool check tablespace [选项]

选项:
  -h, --help    显示帮助

输出列说明:
  Tablespace   - 表空间名称
  Size         - 表空间大小（人类可读）
  Location     - 表空间在文件系统的路径

注意:
  - pg_default: 默认表空间，对应 data/base 目录
  - pg_global: 共享系统表，对应 data/global 目录
  - 自定义表空间: 显示创建时指定的路径

示例:
  pgtool check tablespace
  pgtool check tablespace --format=json

相关:
  查看文件系统磁盘空间请使用系统命令: df -h
EOF
}
