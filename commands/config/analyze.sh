#!/bin/bash
# commands/config/analyze.sh - 分析配置并提供优化建议

#==============================================================================
# 主函数: pgtool_config_analyze
# 分析 PostgreSQL 配置并提供优化建议
#==============================================================================

pgtool_config_analyze() {
    local category=""
    local changed_only=false
    local recommend=false
    local format="${PGTOOL_FORMAT:-table}"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_analyze_help
                return 0
                ;;
            --category)
                shift
                category="$1"
                shift
                ;;
            --changed-only)
                changed_only=true
                shift
                ;;
            --recommend)
                recommend=true
                shift
                ;;
            --format)
                shift
                format="$1"
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            -*)
                pgtool_error "未知选项: $1"
                return $EXIT_INVALID_ARGS
                ;;
            *)
                shift
                ;;
        esac
    done

    # 验证 format 参数
    case "$format" in
        table|json|csv|tsv)
            ;;
        *)
            pgtool_error "不支持的格式: $format"
            return $EXIT_INVALID_ARGS
            ;;
    esac

    pgtool_info "分析 PostgreSQL 配置..."
    echo ""

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 检测系统资源
    local total_ram cpus
    total_ram=$(pgtool_config_detect_memory)
    cpus=$(pgtool_config_detect_cpus)

    echo "系统信息:"
    echo "  内存: $((total_ram / 1024 / 1024))GB"
    echo "  CPU: ${cpus} 核心"
    echo ""

    # 获取 max_connections
    local max_conn
    max_conn=$(pgtool_config_get_max_connections)
    if [[ -z "$max_conn" ]]; then
        max_conn=100
    fi
    echo "  最大连接数: ${max_conn}"
    echo ""

    # 运行推荐检查
    if [[ "$recommend" == true ]]; then
        pgtool_config_analyze_recommendations "$total_ram" "$max_conn"
        echo ""
    fi

    # 显示配置
    pgtool_config_analyze_show_config "$category" "$changed_only" "$format"

    return $EXIT_SUCCESS
}

#==============================================================================
# 运行推荐检查并显示结果
#==============================================================================

pgtool_config_analyze_recommendations() {
    local total_ram="$1"
    local max_conn="${2:-100}"

    echo "配置建议:"
    echo "========"
    echo ""

    local has_issues=false

    # 计算推荐值
    local shared_buffers_rec effective_cache_rec work_mem_rec maintenance_work_mem_rec
    shared_buffers_rec=$(pgtool_config_calc_shared_buffers "$total_ram")
    effective_cache_rec=$(pgtool_config_calc_effective_cache_size "$total_ram")
    work_mem_rec=$(pgtool_config_calc_work_mem "$total_ram" "$max_conn")
    maintenance_work_mem_rec=$(pgtool_config_calc_maintenance_work_mem "$total_ram")

    # 显示推荐值摘要
    echo "基于系统资源的推荐值:"
    echo "  shared_buffers = ${shared_buffers_rec} (当前系统内存的 25%, 最大 8GB)"
    echo "  effective_cache_size = ${effective_cache_rec} (当前系统内存的 50%)"
    echo "  work_mem = ${work_mem_rec} (基于连接数计算)"
    echo "  maintenance_work_mem = ${maintenance_work_mem_rec} (内存的 10% 或 1GB)"
    echo ""

    # 获取当前值并检查
    echo "参数检查:"

    # 检查 shared_buffers
    local current_shared
    current_shared=$(pgtool_config_get_param "shared_buffers")
    if [[ -n "$current_shared" ]]; then
        local result
        result=$(pgtool_config_analyze_param "shared_buffers" "$current_shared" "$total_ram" "$max_conn")
        local status
        status=$(echo "$result" | cut -d'|' -f1)

        if [[ "$status" == "warning" ]]; then
            local rec reason
            rec=$(echo "$result" | cut -d'|' -f2)
            reason=$(echo "$result" | cut -d'|' -f3)
            echo "  [WARN] shared_buffers"
            echo "    当前值: $current_shared"
            echo "    $rec"
            echo "    原因: $reason"
            echo ""
            has_issues=true
        fi
    fi

    # 检查 effective_cache_size
    local current_cache
    current_cache=$(pgtool_config_get_param "effective_cache_size")
    if [[ -n "$current_cache" ]]; then
        local result
        result=$(pgtool_config_analyze_param "effective_cache_size" "$current_cache" "$total_ram" "$max_conn")
        local status
        status=$(echo "$result" | cut -d'|' -f1)

        if [[ "$status" == "warning" ]]; then
            local rec reason
            rec=$(echo "$result" | cut -d'|' -f2)
            reason=$(echo "$result" | cut -d'|' -f3)
            echo "  [WARN] effective_cache_size"
            echo "    当前值: $current_cache"
            echo "    $rec"
            echo "    原因: $reason"
            echo ""
            has_issues=true
        fi
    fi

    # 检查 work_mem
    local current_work
    current_work=$(pgtool_config_get_param "work_mem")
    if [[ -n "$current_work" ]]; then
        local result
        result=$(pgtool_config_analyze_param "work_mem" "$current_work" "$total_ram" "$max_conn")
        local status
        status=$(echo "$result" | cut -d'|' -f1)

        if [[ "$status" == "warning" ]]; then
            local rec reason
            rec=$(echo "$result" | cut -d'|' -f2)
            reason=$(echo "$result" | cut -d'|' -f3)
            echo "  [WARN] work_mem"
            echo "    当前值: $current_work"
            echo "    $rec"
            echo "    原因: $reason"
            echo ""
            has_issues=true
        fi
    fi

    # 检查 maintenance_work_mem
    local current_maint
    current_maint=$(pgtool_config_get_param "maintenance_work_mem")
    if [[ -n "$current_maint" ]]; then
        local result
        result=$(pgtool_config_analyze_param "maintenance_work_mem" "$current_maint" "$total_ram" "$max_conn")
        local status
        status=$(echo "$result" | cut -d'|' -f1)

        if [[ "$status" == "warning" ]]; then
            local rec reason
            rec=$(echo "$result" | cut -d'|' -f2)
            reason=$(echo "$result" | cut -d'|' -f3)
            echo "  [WARN] maintenance_work_mem"
            echo "    当前值: $current_maint"
            echo "    $rec"
            echo "    原因: $reason"
            echo ""
            has_issues=true
        fi
    fi

    # 检查 max_connections
    local result
    result=$(pgtool_config_analyze_param "max_connections" "$max_conn" "$total_ram" "$max_conn")
    local status
    status=$(echo "$result" | cut -d'|' -f1)

    if [[ "$status" == "warning" ]]; then
        local rec reason
        rec=$(echo "$result" | cut -d'|' -f2)
        reason=$(echo "$result" | cut -d'|' -f3)
        echo "  [WARN] max_connections"
        echo "    当前值: $max_conn"
        echo "    $rec"
        echo "    原因: $reason"
        echo ""
        has_issues=true
    fi

    # 检查 random_page_cost
    local current_rpc
    current_rpc=$(pgtool_config_get_param "random_page_cost")
    if [[ -n "$current_rpc" ]]; then
        local result
        result=$(pgtool_config_analyze_param "random_page_cost" "$current_rpc" "$total_ram" "$max_conn")
        local status
        status=$(echo "$result" | cut -d'|' -f1)

        if [[ "$status" == "warning" ]]; then
            local rec reason
            rec=$(echo "$result" | cut -d'|' -f2)
            reason=$(echo "$result" | cut -d'|' -f3)
            echo "  [WARN] random_page_cost"
            echo "    当前值: $current_rpc"
            echo "    $rec"
            echo "    原因: $reason"
            echo ""
            has_issues=true
        fi
    fi

    # 检查 checkpoint_completion_target
    local current_cct
    current_cct=$(pgtool_config_get_param "checkpoint_completion_target")
    if [[ -n "$current_cct" ]]; then
        local result
        result=$(pgtool_config_analyze_param "checkpoint_completion_target" "$current_cct" "$total_ram" "$max_conn")
        local status
        status=$(echo "$result" | cut -d'|' -f1)

        if [[ "$status" == "warning" ]]; then
            local rec reason
            rec=$(echo "$result" | cut -d'|' -f2)
            reason=$(echo "$result" | cut -d'|' -f3)
            echo "  [WARN] checkpoint_completion_target"
            echo "    当前值: $current_cct"
            echo "    $rec"
            echo "    原因: $reason"
            echo ""
            has_issues=true
        fi
    fi

    if [[ "$has_issues" == false ]]; then
        echo "  所有检查项状态正常"
        echo ""
    fi
}

#==============================================================================
# 显示配置
#==============================================================================

pgtool_config_analyze_show_config() {
    local category="$1"
    local changed_only="$2"
    local format="$3"

    echo "配置详情:"
    echo "========"
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "config" "analyze"); then
        pgtool_fatal "SQL 文件未找到: config/analyze"
    fi

    # 设置 :category 参数
    local category_filter=""
    if [[ -n "$category" ]]; then
        category_filter="$category"
    fi

    # 执行 SQL 查询
    local result exit_code
    local format_args
    format_args=$(pgtool_pset_args "$format")

    if [[ "$changed_only" == true ]]; then
        # 使用修改过的配置的 SQL
        local changed_sql
        changed_sql="SELECT name, setting, COALESCE(unit, '') as unit, context, vartype, boot_val as default, category, short_desc FROM pg_settings WHERE setting != boot_val ORDER BY category, name"

        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            -c "$changed_sql" \
            --pset=pager=off \
            $format_args \
            2>&1)
        exit_code=$?
    else
        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            -v category="'$category_filter'" \
            --pset=pager=off \
            $format_args \
            2>&1)
        exit_code=$?
    fi

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"
}

#==============================================================================
# 帮助函数
#==============================================================================

pgtool_config_analyze_help() {
    cat << 'EOF'
分析 PostgreSQL 配置并提供优化建议

用法: pgtool config analyze [选项]

选项:
  -h, --help              显示帮助
      --category=<cat>    按类别过滤配置 (memory/storage/network/query)
      --changed-only      仅显示已修改的配置
      --recommend         显示配置建议和推荐值
      --format=<fmt>      输出格式 (table, json, csv, tsv)

说明:
  该命令分析当前 PostgreSQL 配置，检测系统资源 (内存、CPU)，
  并根据最佳实践提供优化建议。

  当使用 --recommend 选项时，会检查关键参数:
    - shared_buffers: 应设置为内存的 25%
    - effective_cache_size: 应设置为内存的 50%
    - work_mem: 根据连接数计算
    - maintenance_work_mem: 应设置为内存的 10% 或 1GB
    - random_page_cost: 根据磁盘类型调整 (SSD/HDD)
    - checkpoint_completion_target: 建议 0.9 避免 I/O 尖峰

示例:
  # 分析所有配置
  pgtool config analyze

  # 仅分析内存相关配置并显示建议
  pgtool config analyze --category=memory --recommend

  # 查看已修改的配置 (JSON 格式)
  pgtool config analyze --changed-only --format=json

  # 导出配置分析结果到 CSV
  pgtool config analyze --format=csv > config_analysis.csv

输出字段:
  name        - 参数名称
  setting     - 当前设置值
  unit        - 单位
  context     - 修改上下文 (internal, postmaster, etc.)
  vartype     - 值类型 (bool, integer, real, string, enum)
  default     - 默认值
  category    - 参数类别
  short_desc  - 简短描述
EOF
}
