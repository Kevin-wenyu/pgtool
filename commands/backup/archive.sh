#!/bin/bash
# commands/backup/archive.sh - 检查 WAL 归档状态

#==============================================================================
# 主函数
#==============================================================================

pgtool_backup_archive() {
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_backup_archive_help
                return 0
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "检查 WAL 归档状态..."
    echo ""

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 检查 archive_mode 设置
    local archive_mode
    archive_mode=$(pgtool_pg_query_one "SHOW archive_mode")

    if [[ $? -ne 0 ]]; then
        pgtool_error "无法获取 archive_mode 设置"
        return $EXIT_SQL_ERROR
    fi

    pgtool_kv "Archive Mode" "$archive_mode"

    # 检查 archive_command 设置
    local archive_command
    archive_command=$(pgtool_pg_query_one "SHOW archive_command")

    if [[ $? -ne 0 ]]; then
        pgtool_error "无法获取 archive_command 设置"
        return $EXIT_SQL_ERROR
    fi

    pgtool_kv "Archive Command" "$archive_command"
    echo ""

    # 如果归档未启用，给出提示
    if [[ "$archive_mode" == "off" ]]; then
        pgtool_warn "归档模式未启用 (archive_mode = off)"
        pgtool_info "要启用 WAL 归档，请在 postgresql.conf 中设置:"
        pgtool_info "  archive_mode = on"
        pgtool_info "  archive_command = '...'"
        echo ""
    fi

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "backup" "archive"); then
        pgtool_fatal "SQL文件未找到: backup/archive"
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

    # 检查是否有 WARNING 状态
    if echo "$result" | grep -q "WARNING"; then
        return 1
    fi

    return $EXIT_SUCCESS
}

#==============================================================================
# 帮助函数
#==============================================================================

pgtool_backup_archive_help() {
    cat <<EOF
检查 WAL 归档状态

检查 PostgreSQL WAL (Write-Ahead Log) 归档器的状态，包括：
- archive_mode 配置参数
- archive_command 配置参数
- 已归档 WAL 文件数量
- 归档失败次数
- 上次成功归档时间
- 上次失败时间
- 最后归档的 WAL 文件名

用法: pgtool backup archive [选项]

选项:
  -h, --help              显示帮助
      --format FORMAT     输出格式 (table|json|csv|tsv)

输出字段:
  Archived       - 已成功归档的 WAL 文件数量
  Failed         - 归档失败的 WAL 文件数量
  Last Archived  - 上次成功归档的时间
  Last Failed    - 上次归档失败的时间
  Last WAL       - 最后归档的 WAL 文件名
  Status         - 状态 (OK/WARNING)

状态说明:
  OK       - 归档正常，无失败记录
  WARNING  - 存在归档失败或超过5分钟未归档

环境变量:
  PGTOOL_FORMAT     默认输出格式
  PGTOOL_TIMEOUT    SQL 执行超时时间 (默认: 30秒)

示例:
  pgtool backup archive
  pgtool backup archive --format=json

相关配置:
  在 postgresql.conf 中启用归档:
    archive_mode = on
    archive_command = 'cp %p /path/to/archive/%f'
    # 或使用 pgBackRest/Barman:
    archive_command = 'pgbackrest --stanza=main archive-push %p'

依赖:
  需要连接到 PostgreSQL 数据库
  需要 pg_stat_archiver 视图权限 (PostgreSQL 9.4+)
EOF
}
