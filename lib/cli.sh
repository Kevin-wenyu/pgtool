#!/bin/bash
# lib/cli.sh - 命令分发器

# 必须先加载 core.sh 和 log.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# 命令组定义
#==============================================================================

# 支持的命令组
PGTOOL_GROUPS=("check" "stat" "admin" "analyze" "monitor" "user" "plugin")

# 命令组描述（用于帮助）
pgtool_group_desc() {
    local group="$1"
    case "$group" in
        check)   echo "健康检查 - 检查数据库健康状态" ;;
        stat)    echo "统计信息 - 查看数据库统计" ;;
        admin)   echo "管理操作 - 执行管理任务" ;;
        analyze) echo "分析诊断 - 分析问题并建议" ;;
        monitor) echo "实时监控 - 实时监控数据库状态" ;;
        user)    echo "用户管理 - 用户、角色和权限管理" ;;
        plugin)  echo "插件管理 - 管理扩展插件" ;;
        *)       echo "" ;;
    esac
}

#==============================================================================
# 全局选项
#==============================================================================

PGTOOL_GLOBAL_OPTS="
全局选项:
  -h, --help              显示帮助信息
  -v, --version           显示版本
  -c, --config FILE       指定配置文件
      --format FORMAT     输出格式 (table|json|csv|tsv)
      --timeout SECONDS   命令超时时间 (默认: $PGTOOL_DEFAULT_TIMEOUT)
      --color auto|yes|no 颜色输出 (默认: auto)
      --log-level LEVEL   日志级别 (debug|info|warn|error)
      --host HOST         数据库主机
      --port PORT         数据库端口
      --user USER         数据库用户
      --dbname NAME       数据库名称
"

#==============================================================================
# 全局选项解析
#==============================================================================

# 解析全局选项
# 返回：剩余参数（命令部分）
pgtool_parse_global_opts() {
    local -a remaining=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_global_help
                exit $EXIT_SUCCESS
                ;;
            -v|--version)
                pgtool_version
                exit $EXIT_SUCCESS
                ;;
            -c|--config)
                shift
                PGTOOL_CONFIG_FILE="${1:-}"
                if [[ -z "$PGTOOL_CONFIG_FILE" ]]; then
                    pgtool_fatal "--config 需要参数"
                fi
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="${1:-}"
                if [[ -z "$PGTOOL_FORMAT" ]]; then
                    pgtool_fatal "--format 需要参数"
                fi
                shift
                ;;
            --timeout)
                shift
                PGTOOL_TIMEOUT="${1:-}"
                if [[ -z "$PGTOOL_TIMEOUT" ]]; then
                    pgtool_fatal "--timeout 需要参数"
                fi
                if ! is_int "$PGTOOL_TIMEOUT"; then
                    pgtool_fatal "--timeout 必须是整数"
                fi
                shift
                ;;
            --color)
                shift
                PGTOOL_COLOR="${1:-}"
                if [[ -z "$PGTOOL_COLOR" ]]; then
                    pgtool_fatal "--color 需要参数"
                fi
                shift
                ;;
            --log-level)
                shift
                PGTOOL_LOG_LEVEL="${1:-}"
                if [[ -z "$PGTOOL_LOG_LEVEL" ]]; then
                    pgtool_fatal "--log-level 需要参数"
                fi
                shift
                ;;
            --host)
                shift
                PGTOOL_HOST="${1:-}"
                shift
                ;;
            --port)
                shift
                PGTOOL_PORT="${1:-}"
                shift
                ;;
            --user)
                shift
                PGTOOL_USER="${1:-}"
                shift
                ;;
            --dbname)
                shift
                PGTOOL_DATABASE="${1:-}"
                shift
                ;;
            --)
                shift
                remaining+=("$@")
                break
                ;;
            -*)
                pgtool_fatal "未知选项: $1"
                ;;
            *)
                remaining+=("$1")
                shift
                ;;
        esac
    done

    # 返回剩余参数
    echo "${remaining[*]}"
}

#==============================================================================
# 帮助信息
#==============================================================================

# 全局帮助
pgtool_global_help() {
    cat <<EOF
$PGTOOL_NAME - PostgreSQL CLI Toolkit v$PGTOOL_VERSION

用法: $PGTOOL_NAME <命令组> <命令> [选项...]

命令组:
EOF

    local group
    for group in "${PGTOOL_GROUPS[@]}"; do
        printf "  %-10s %s\n" "$group" "$(pgtool_group_desc "$group")"
    done

    cat <<EOF

$PGTOOL_GLOBAL_OPTS

使用 '$PGTOOL_NAME <命令组> --help' 查看组内命令列表
使用 '$PGTOOL_NAME <命令组> <命令> --help' 查看命令帮助

示例:
  $PGTOOL_NAME check xid
  $PGTOOL_NAME stat activity --format=json
  $PGTOOL_NAME admin kill-blocking --force

EOF
}

# 显示版本
pgtool_version() {
    echo "$PGTOOL_NAME version $PGTOOL_VERSION"
}

#==============================================================================
# 命令分发
#==============================================================================

# 主分发函数
pgtool_dispatch() {
    if [[ $# -eq 0 ]]; then
        pgtool_global_help
        exit $EXIT_SUCCESS
    fi

    local group="$1"
    shift

    # 检查是否为有效组
    if ! array_contains "$group" "${PGTOOL_GROUPS[@]}"; then
        pgtool_error "未知命令组: $group"
        pgtool_error "有效命令组: ${PGTOOL_GROUPS[*]}"
        exit $EXIT_INVALID_ARGS
    fi

    # 加载命令组索引
    local index_file="$PGTOOL_ROOT/commands/$group/index.sh"
    if [[ ! -f "$index_file" ]]; then
        pgtool_fatal "命令组模块缺失: $index_file"
    fi

    source "$index_file"

    # 如果没有子命令，显示组帮助
    if [[ $# -eq 0 ]]; then
        if type "pgtool_${group}_help" &>/dev/null; then
            "pgtool_${group}_help"
        else
            pgtool_error "命令组 $group 没有帮助信息"
        fi
        exit $EXIT_SUCCESS
    fi

    # 处理组级选项
    case "$1" in
        -h|--help)
            if type "pgtool_${group}_help" &>/dev/null; then
                "pgtool_${group}_help"
            fi
            exit $EXIT_SUCCESS
            ;;
    esac

    local command="$1"
    shift

    # 验证命令存在
    if ! pgtool_command_exists "$group" "$command"; then
        pgtool_error "未知命令: $group $command"
        if type "pgtool_${group}_help" &>/dev/null; then
            echo
            "pgtool_${group}_help"
        fi
        exit $EXIT_NOT_FOUND
    fi

    # 加载并执行命令
    local cmd_file_name="${command//-/_}"
    local cmd_file="$PGTOOL_ROOT/commands/$group/$cmd_file_name.sh"
    if [[ ! -f "$cmd_file" ]]; then
        pgtool_fatal "命令文件缺失: $cmd_file"
    fi

    source "$cmd_file"

    local func_name="pgtool_${group}_${command//-/_}"
    if ! type "$func_name" &>/dev/null; then
        pgtool_fatal "命令函数未定义: $func_name"
    fi

    # 执行命令
    "$func_name" "$@"
}

# 检查命令是否存在
pgtool_command_exists() {
    local group="$1"
    local command="$2"

    # 获取组命令列表变量名 (兼容 Bash 3.x)
    local group_upper
    group_upper=$(echo "$group" | tr '[:lower:]' '[:upper:]')
    local var_name="PGTOOL_${group_upper}_COMMANDS"

    # 获取变量值 (兼容 Bash 3.x)
    local commands
    commands=$(eval echo "\$$var_name")

    if [[ -z "$commands" ]]; then
        return 1
    fi

    # 检查命令是否在列表中
    if [[ "$commands" == *"$command"* ]]; then
        return 0
    fi

    return 1
}

# 获取命令列表
pgtool_list_commands() {
    local group="$1"
    local group_upper
    group_upper=$(echo "$group" | tr '[:lower:]' '[:upper:]')
    local var_name="PGTOOL_${group_upper}_COMMANDS"
    local commands
    commands=$(eval echo "\$$var_name")

    if [[ -z "$commands" ]]; then
        return 1
    fi

    # 解析命令列表
    local item
    local cmd
    local desc

    IFS=',' read -ra CMD_ARRAY <<< "$commands"
    for item in "${CMD_ARRAY[@]}"; do
        cmd="${item%%:*}"
        desc="${item##*:}"
        printf "  %-20s %s\n" "$cmd" "$desc"
    done
}

#==============================================================================
# 选项处理辅助
#==============================================================================

# 解析标准选项
pgtool_parse_opts() {
    local -n opts_ref=$1
    local -n args_ref=$2
    shift 2

    opts_ref=()
    args_ref=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                return 1  # 需要显示帮助
                ;;
            -*)
                opts_ref+=("$1")
                if [[ $# -gt 1 ]]; then
                    # 检查下一个参数是否是选项值
                    case "$2" in
                        -*) ;;
                        *)
                            opts_ref+=("$2")
                            shift
                            ;;
                    esac
                fi
                shift
                ;;
            *)
                args_ref+=("$1")
                shift
                ;;
        esac
    done
}

# 获取选项值
pgtool_get_opt() {
    local opt="$1"
    shift
    local -a opts=("$@")
    local i

    for i in "${!opts[@]}"; do
        if [[ "${opts[$i]}" == "$opt" ]]; then
            if [[ $((i + 1)) -lt ${#opts[@]} ]]; then
                echo "${opts[$i+1]}"
                return 0
            fi
        fi
    done

    return 1
}

# 检查选项是否存在
pgtool_has_opt() {
    local opt="$1"
    shift
    local -a opts=("$@")
    local item

    for item in "${opts[@]}"; do
        if [[ "$item" == "$opt" ]]; then
            return 0
        fi
    done

    return 1
}
