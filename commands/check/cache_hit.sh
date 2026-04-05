#!/bin/bash
# commands/check/cache_hit.sh - 检查缓存命中率

#==============================================================================
# 默认阈值
#==============================================================================

PGTOOL_CACHE_HIT_WARNING="${PGTOOL_CACHE_HIT_WARNING:-95}"
PGTOOL_CACHE_HIT_CRITICAL="${PGTOOL_CACHE_HIT_CRITICAL:-90}"

#==============================================================================
# 主函数
#==============================================================================

pgtool_check_cache_hit() {
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_cache_hit_help
                return 0
                ;;
            --threshold-warning)
                shift
                PGTOOL_CACHE_HIT_WARNING="$1"
                shift
                ;;
            --threshold-critical)
                shift
                PGTOOL_CACHE_HIT_CRITICAL="$1"
                shift
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

    pgtool_info "检查缓存命中率..."
    pgtool_info "警告阈值: ${PGTOOL_CACHE_HIT_WARNING}%"
    pgtool_info "危险阈值: ${PGTOOL_CACHE_HIT_CRITICAL}%"
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "cache_hit"); then
        pgtool_fatal "SQL文件未找到: check/cache_hit"
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

    # 检查是否有警告
    if echo "$result" | grep -q "CRITICAL"; then
        return 2
    elif echo "$result" | grep -q "WARNING"; then
        return 1
    fi

    return $EXIT_SUCCESS
}

# 帮助函数
pgtool_check_cache_hit_help() {
    cat <<EOF
检查缓存命中率

检查 PostgreSQL shared_buffers 的缓存命中率。
低缓存命中率通常意味着 shared_buffers 设置过小，
或者存在大量全表扫描导致频繁读取磁盘。

推荐命中率：
  - 95%+ : 正常
  - 90-95%: 需要关注
  - <90%  : 需要优化

用法: pgtool check cache-hit [选项]

选项:
  -h, --help              显示帮助
      --threshold-warning NUM   警告阈值 (默认: 95)
      --threshold-critical NUM  危险阈值 (默认: 90)

环境变量:
  PGTOOL_CACHE_HIT_WARNING   警告阈值
  PGTOOL_CACHE_HIT_CRITICAL  危险阈值

输出:
  OK       - 命中率正常
  WARNING  - 命中率低于警告阈值
  CRITICAL - 命中率低于危险阈值

示例:
  pgtool check cache-hit
  pgtool check cache-hit --threshold-warning=96 --threshold-critical=92
EOF
}
