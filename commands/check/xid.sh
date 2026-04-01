#!/bin/bash
# commands/check/xid.sh - 检查 XID 年龄

#==============================================================================
# 默认阈值
#==============================================================================

PGTOOL_XID_WARNING="${PGTOOL_XID_WARNING:-1500000000}"
PGTOOL_XID_CRITICAL="${PGTOOL_XID_CRITICAL:-2000000000}"

#==============================================================================
# 主函数
#==============================================================================

pgtool_check_xid() {
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_xid_help
                return 0
                ;;
            --threshold-warning)
                shift
                PGTOOL_XID_WARNING="$1"
                shift
                ;;
            --threshold-critical)
                shift
                PGTOOL_XID_CRITICAL="$1"
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

    pgtool_info "检查数据库 XID 年龄..."
    pgtool_info "警告阈值: $PGTOOL_XID_WARNING"
    pgtool_info "危险阈值: $PGTOOL_XID_CRITICAL"
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "xid"); then
        pgtool_fatal "SQL文件未找到: check/xid"
    fi

    # 测试连接（静默）
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 执行 SQL，使用表格格式
    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --pset=pager=off \
        --pset=format=aligned \
        --pset=border=2 \
        --pset=null='<null>' \
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

    # 检查是否有警告
    if echo "$result" | grep -q "WARNING"; then
        return 1
    elif echo "$result" | grep -q "CRITICAL"; then
        return 2
    fi

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_check_xid_help() {
    cat <<EOF
检查事务ID (XID) 年龄

检查数据库的 datfrozenxid 年龄，预警 XID 回卷风险。
PostgreSQL 使用 32 位事务 ID，最大值为 2^32 (约 42 亿)。
当 XID 接近上限时需要执行 VACUUM FREEZE。

用法: pgtool check xid [选项]

选项:
  -h, --help              显示帮助
      --threshold-warning NUM   警告阈值 (默认: 1500000000)
      --threshold-critical NUM  危险阈值 (默认: 2000000000)

环境变量:
  PGTOOL_XID_WARNING      警告阈值
  PGTOOL_XID_CRITICAL     危险阈值

输出:
  OK       - XID 年龄正常
  WARNING  - XID 年龄超过警告阈值
  CRITICAL - XID 年龄接近危险值，需要立即处理

示例:
  pgtool check xid
  pgtool check xid --threshold-warning=1000000000
EOF
}
