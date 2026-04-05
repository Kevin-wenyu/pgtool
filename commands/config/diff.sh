#!/bin/bash
# commands/config/diff.sh - 比较两个 PostgreSQL 实例的配置差异

#==============================================================================
# 主函数
#==============================================================================

pgtool_config_diff() {
    local target_host=""
    local target_port="5432"
    local target_db="postgres"
    local target_user=""
    local category=""
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_diff_help
                return 0
                ;;
            --target-host)
                shift
                target_host="$1"
                shift
                ;;
            --target-port)
                shift
                target_port="$1"
                shift
                ;;
            --target-db)
                shift
                target_db="$1"
                shift
                ;;
            --target-user)
                shift
                target_user="$1"
                shift
                ;;
            --category)
                shift
                category="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                if [[ $# -gt 1 ]]; then
                    case "$2" in
                        -*) ;;
                        *)
                            opts+=("$2")
                            shift
                            ;;
                    esac
                fi
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # 验证必需参数
    if [[ -z "$target_host" ]]; then
        pgtool_error "缺少必需参数: --target-host"
        pgtool_info "用法: pgtool config diff --target-host=<主机> [--target-port=<端口>] [--target-db=<数据库>] [--target-user=<用户>]"
        return $EXIT_INVALID_ARGS
    fi

    # 如果未指定目标用户，使用当前用户
    if [[ -z "$target_user" ]]; then
        target_user="$PGTOOL_USER"
    fi

    # 测试源数据库连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 获取源数据库配置
    pgtool_info "正在获取源数据库 ($PGTOOL_HOST:$PGTOOL_PORT/$PGTOOL_DATABASE) 配置..."
    local source_config
    source_config=$(pgtool_config_diff_get_config "$PGTOOL_HOST" "$PGTOOL_PORT" "$PGTOOL_DATABASE" "$PGTOOL_USER" "$category")
    if [[ $? -ne 0 ]]; then
        pgtool_error "获取源数据库配置失败"
        return $EXIT_SQL_ERROR
    fi

    # 获取目标数据库配置
    pgtool_info "正在获取目标数据库 ($target_host:$target_port/$target_db) 配置..."
    local target_config
    target_config=$(pgtool_config_diff_get_config "$target_host" "$target_port" "$target_db" "$target_user" "$category")
    if [[ $? -ne 0 ]]; then
        pgtool_error "获取目标数据库配置失败"
        return $EXIT_SQL_ERROR
    fi

    # 比较配置
    pgtool_config_diff_compare "$source_config" "$target_config" "$PGTOOL_HOST" "$target_host"

    return $EXIT_SUCCESS
}

# 获取配置
pgtool_config_diff_get_config() {
    local host="$1"
    local port="$2"
    local db="$3"
    local user="$4"
    local category="$5"

    local sql="SELECT name, setting, boot_val, unit, context, vartype, source, category FROM pg_settings"

    if [[ -n "$category" ]]; then
        sql="$sql WHERE category ILIKE '%${category}%'"
    fi

    sql="$sql ORDER BY category, name"

    local conn_opts=(
        "--host=$host"
        "--port=$port"
        "--username=$user"
        "--dbname=$db"
        "--no-psqlrc"
        "--no-align"
    )

    timeout "$PGTOOL_TIMEOUT" psql \
        "${conn_opts[@]}" \
        --command="$sql" \
        --pset=pager=off \
        --quiet 2>&1
}

# 比较配置
pgtool_config_diff_compare() {
    local source_config="$1"
    local target_config="$2"
    local source_host="$3"
    local target_host="$4"

    # 使用关联数组存储配置
    declare -A source_params
    declare -A target_params

    # 解析源配置
    while IFS='|' read -r name setting boot_val unit context vartype source_val category; do
        [[ -z "$name" ]] && continue
        [[ "$name" == "name" ]] && continue
        name=$(echo "$name" | tr -d ' ')
        source_params["$name"]="$setting|$boot_val|$unit|$context|$vartype|$source_val|$category"
    done <<< "$source_config"

    # 解析目标配置
    while IFS='|' read -r name setting boot_val unit context vartype source_val category; do
        [[ -z "$name" ]] && continue
        [[ "$name" == "name" ]] && continue
        name=$(echo "$name" | tr -d ' ')
        target_params["$name"]="$setting|$boot_val|$unit|$context|$vartype|$source_val|$category"
    done <<< "$target_config"

    # 比较并显示差异
    local has_diff=0

    echo ""
    echo "配置差异对比"
    echo "============"
    echo "源: $source_host"
    echo "目标: $target_host"
    echo ""

    # 检查源有但目标没有的参数，以及值不同的参数
    for param in "${!source_params[@]}"; do
        if [[ -z "${target_params[$param]:-}" ]]; then
            # 目标没有的参数
            if [[ $has_diff -eq 0 ]]; then
                echo "仅在源数据库存在的参数:"
                echo ""
            fi
            has_diff=1
            IFS='|' read -r setting boot_val unit context vartype source_val category <<< "${source_params[$param]}"
            echo "  $param:"
            echo "    值: $setting"
            echo "    类别: $category"
            echo ""
        else
            # 两边都有的参数，比较值
            IFS='|' read -r source_setting source_boot_val source_unit source_context source_vartype source_source_val source_category <<< "${source_params[$param]}"
            IFS='|' read -r target_setting target_boot_val target_unit target_context target_vartype target_source_val target_category <<< "${target_params[$param]}"

            # 去除空格后比较
            local source_val_trimmed=$(echo "$source_setting" | tr -d ' ')
            local target_val_trimmed=$(echo "$target_setting" | tr -d ' ')

            if [[ "$source_val_trimmed" != "$target_val_trimmed" ]]; then
                if [[ $has_diff -eq 0 ]]; then
                    echo "值不同的参数:"
                    echo ""
                    has_diff=1
                fi
                echo "  $param:"
                echo "    源: $source_setting"
                echo "    目标: $target_setting"
                if [[ -n "$source_unit" ]]; then
                    echo "    单位: $source_unit"
                fi
                echo ""
            fi
        fi
    done

    # 检查目标有但源没有的参数
    local has_target_only=0
    for param in "${!target_params[@]}"; do
        if [[ -z "${source_params[$param]:-}" ]]; then
            if [[ $has_target_only -eq 0 ]]; then
                echo "仅在目标数据库存在的参数:"
                echo ""
                has_target_only=1
                has_diff=1
            fi
            IFS='|' read -r setting boot_val unit context vartype source_val category <<< "${target_params[$param]}"
            echo "  $param:"
            echo "    值: $setting"
            echo "    类别: $category"
            echo ""
        fi
    done

    if [[ $has_diff -eq 0 ]]; then
        echo "两个数据库的配置完全相同。"
        echo ""
    fi

    # 显示统计信息
    echo "统计:"
    echo "  源数据库参数数: ${#source_params[@]}"
    echo "  目标数据库参数数: ${#target_params[@]}"
    echo ""
}

# 帮助函数
pgtool_config_diff_help() {
    cat <<EOF
比较两个 PostgreSQL 实例的配置差异

对比源数据库（当前连接）和目标数据库的配置参数，显示：
- 仅在源数据库存在的参数
- 仅在目标数据库存在的参数
- 值不同的参数

用法: pgtool config diff --target-host=<主机> [选项]

必需参数:
  --target-host=HOST      目标数据库主机地址

可选参数:
  --target-port=PORT      目标数据库端口 (默认: 5432)
  --target-db=DATABASE    目标数据库名称 (默认: postgres)
  --target-user=USER      目标数据库用户 (默认: 当前用户)
  --category=CATEGORY     按类别过滤 (如: memory, storage, network, query)

全局选项:
  --format=FORMAT         输出格式 (table|json|csv|tsv)
  --timeout=SECONDS       超时时间
  -h, --help              显示帮助

示例:
  # 比较两个实例的配置
  pgtool config diff --target-host=prod-db.example.com

  # 指定目标端口和用户
  pgtool config diff --target-host=192.168.1.100 --target-port=5433 --target-user=admin

  # 只比较内存相关配置
  pgtool config diff --target-host=db2.example.com --category=memory

  # 完整示例
  pgtool config diff --target-host=prod-db.example.com \
    --target-port=5432 \
    --target-db=postgres \
    --target-user=postgres \
    --category=memory

注意事项:
  - 源数据库使用当前连接的参数
  - 目标数据库需要额外的连接参数
  - 比较时会去除值的空格
  - 不同版本的 PostgreSQL 可能有不同的参数集
EOF
}
