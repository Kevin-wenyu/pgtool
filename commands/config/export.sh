#!/bin/bash
# commands/config/export.sh - 导出 PostgreSQL 配置

#==============================================================================
# 主函数
#==============================================================================

pgtool_config_export() {
    local category=""
    local changed_only=false
    local format="${PGTOOL_FORMAT:-conf}"
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_export_help
                return 0
                ;;
            --category)
                shift
                category="$1"
                shift
                ;;
            --category=*)
                category="${1#*=}"
                shift
                ;;
            --changed-only)
                changed_only=true
                shift
                ;;
            --format)
                shift
                format="$1"
                shift
                ;;
            --format=*)
                format="${1#*=}"
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

    # 验证格式
    if [[ "$format" != "conf" && "$format" != "alter" && "$format" != "json" ]]; then
        pgtool_error "无效格式: $format"
        pgtool_info "支持的格式: conf, alter, json"
        return $EXIT_INVALID_ARGS
    fi

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 构建 SQL 查询
    local sql
    sql=$(pgtool_config_export_build_sql "$category" "$changed_only")

    # 执行查询
    local result
    result=$(pgtool_pg_exec "$sql" --tuples-only --quiet 2>&1)

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        pgtool_error "查询失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # 格式化输出
    case "$format" in
        conf)
            pgtool_config_export_format_conf "$result"
            ;;
        alter)
            pgtool_config_export_format_alter "$result"
            ;;
        json)
            pgtool_config_export_format_json "$result"
            ;;
    esac

    return $EXIT_SUCCESS
}

#==============================================================================
# 辅助函数
#==============================================================================

# 构建 SQL 查询
pgtool_config_export_build_sql() {
    local category="$1"
    local changed_only="$2"

    local sql="SELECT name, setting, COALESCE(unit, '') AS unit, context, vartype, boot_val, source, category, short_desc FROM pg_settings WHERE 1=1"

    # 添加类别过滤
    if [[ -n "$category" ]]; then
        sql="$sql AND category ILIKE '%$category%'"
    fi

    # 添加已修改过滤
    if [[ "$changed_only" == "true" ]]; then
        sql="$sql AND source != 'default' AND source IS NOT NULL"
    fi

    sql="$sql ORDER BY category, name"

    echo "$sql"
}

# 格式化为 postgresql.conf 格式
pgtool_config_export_format_conf() {
    local data="$1"

    # 打印文件头
    echo "# PostgreSQL Configuration Export"
    echo "# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "# Database: $PGTOOL_DATABASE"
    echo "# Host: $PGTOOL_HOST"
    echo ""

    local current_category=""
    local line

    while IFS='|' read -r name setting unit context vartype default_val source category short_desc; do
        # 去除空白
        name=$(echo "$name" | tr -d ' ')
        setting=$(echo "$setting" | tr -d ' ')
        unit=$(echo "$unit" | tr -d ' ')
        context=$(echo "$context" | tr -d ' ')
        vartype=$(echo "$vartype" | tr -d ' ')
        default_val=$(echo "$default_val" | tr -d ' ')
        source=$(echo "$source" | tr -d ' ')
        category=$(echo "$category" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        short_desc=$(echo "$short_desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # 跳过空行
        [[ -z "$name" ]] && continue

        # 新类别时打印类别标题
        if [[ "$category" != "$current_category" ]]; then
            current_category="$category"
            echo ""
            echo "#------------------------------------------------------------------------------"
            echo "# $category"
            echo "#------------------------------------------------------------------------------"
        fi

        # 打印注释（描述）
        if [[ -n "$short_desc" ]]; then
            echo "# $short_desc"
        fi
        echo "# Type: $vartype, Context: $context"
        if [[ -n "$unit" ]]; then
            echo "# Unit: $unit"
        fi

        # 打印配置项
        if [[ "$vartype" == "string" ]]; then
            # 字符串值需要引号
            echo "$name = '$setting'"
        else
            if [[ -n "$unit" ]]; then
                echo "$name = $setting$unit"
            else
                echo "$name = $setting"
            fi
        fi
        echo ""
    done <<< "$data"
}

# 格式化为 ALTER SYSTEM 格式
pgtool_config_export_format_alter() {
    local data="$1"

    # 打印文件头
    echo "-- PostgreSQL Configuration Export (ALTER SYSTEM format)"
    echo "-- Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "-- Database: $PGTOOL_DATABASE"
    echo "-- Host: $PGTOOL_HOST"
    echo ""
    echo "-- NOTE: These commands require superuser privileges"
    echo "-- Run 'SELECT pg_reload_conf();' after executing to apply changes (if applicable)"
    echo ""

    local line

    while IFS='|' read -r name setting unit context vartype default_val source category short_desc; do
        # 去除空白
        name=$(echo "$name" | tr -d ' ')
        setting=$(echo "$setting" | tr -d ' ')
        unit=$(echo "$unit" | tr -d ' ')
        context=$(echo "$context" | tr -d ' ')
        vartype=$(echo "$vartype" | tr -d ' ')

        # 跳过空行
        [[ -z "$name" ]] && continue

        # 构建值
        local value
        if [[ "$vartype" == "string" ]]; then
            value="'$setting'"
        else
            if [[ -n "$unit" ]]; then
                value="'$setting$unit'"
            else
                value="'$setting'"
            fi
        fi

        # 打印 ALTER SYSTEM 命令
        echo "ALTER SYSTEM SET $name = $value;"
    done <<< "$data"

    echo ""
    echo "-- Apply changes"
    echo "-- SELECT pg_reload_conf();  -- For sighup context parameters"
    echo "-- -- OR restart PostgreSQL for postmaster context parameters"
}

# 格式化为 JSON 格式
pgtool_config_export_format_json() {
    local data="$1"

    local first=true
    local line

    echo "["

    while IFS='|' read -r name setting unit context vartype default_val source category short_desc; do
        # 去除空白
        name=$(echo "$name" | tr -d ' ')
        setting=$(echo "$setting" | tr -d ' ')
        unit=$(echo "$unit" | tr -d ' ')
        context=$(echo "$context" | tr -d ' ')
        vartype=$(echo "$vartype" | tr -d ' ')
        default_val=$(echo "$default_val" | tr -d ' ')
        source=$(echo "$source" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        category=$(echo "$category" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        short_desc=$(echo "$short_desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # 跳过空行
        [[ -z "$name" ]] && continue

        # 添加逗号分隔
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi

        # 转义特殊字符
        local escaped_desc
        escaped_desc=$(echo "$short_desc" | sed 's/"/\\"/g')

        # 打印 JSON 对象
        echo -n "  {"
        echo -n "\"name\": \"$name\", "
        echo -n "\"value\": \"$setting\", "
        echo -n "\"unit\": \"$unit\", "
        echo -n "\"context\": \"$context\", "
        echo -n "\"vartype\": \"$vartype\", "
        echo -n "\"default\": \"$default_val\", "
        echo -n "\"source\": \"$source\", "
        echo -n "\"category\": \"$category\", "
        echo -n "\"description\": \"$escaped_desc\""
        echo -n "}"
    done <<< "$data"

    echo ""
    echo "]"
}

# 帮助函数
pgtool_config_export_help() {
    cat <<EOF
导出 PostgreSQL 配置

以指定格式导出 PostgreSQL 配置参数。

用法: pgtool config export [选项]

选项:
  -h, --help                显示帮助
  --category=<category>     按类别过滤（如 memory, storage, network）
  --changed-only            仅导出已修改的配置
  --format=<format>         输出格式 (conf|alter|json)，默认 conf

格式说明:
  conf      - postgresql.conf 格式 (name = value)
  alter     - ALTER SYSTEM SQL 格式
  json      - JSON 格式，包含元数据

示例:
  pgtool config export                                    # 导出所有配置
  pgtool config export --format=conf                      # 导出为 conf 格式
  pgtool config export --format=alter                     # 导出为 SQL 格式
  pgtool config export --format=json                      # 导出为 JSON 格式
  pgtool config export --category=memory                  # 仅导出内存相关配置
  pgtool config export --changed-only                     # 仅导出已修改的配置
  pgtool config export --category=storage --format=json   # 导出存储配置为 JSON

配置上下文说明:
  postmaster      - 需要重启 PostgreSQL 服务
  sighup          - 需要执行 pg_reload_conf() 或重启
  superuser       - 即时生效 (需要超级用户权限)
  user            - 即时生效 (可在会话级别设置)
EOF
}
