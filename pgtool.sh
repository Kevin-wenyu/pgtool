#!/bin/bash
# pgtool.sh - PostgreSQL CLI Toolkit
# 类似 kubectl 的 PostgreSQL 运维工具

set -euo pipefail

#==============================================================================
# 初始化
#==============================================================================

# 获取脚本所在目录
PGTOOL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PGTOOL_SCRIPT_DIR

# 加载核心模块
source "$PGTOOL_SCRIPT_DIR/lib/core.sh"
source "$PGTOOL_SCRIPT_DIR/lib/log.sh"
source "$PGTOOL_SCRIPT_DIR/lib/util.sh"
source "$PGTOOL_SCRIPT_DIR/lib/output.sh"
source "$PGTOOL_SCRIPT_DIR/lib/pg.sh"
source "$PGTOOL_SCRIPT_DIR/lib/plugin.sh"
source "$PGTOOL_SCRIPT_DIR/lib/cli.sh"

#==============================================================================
# 配置加载
#==============================================================================

# 加载配置文件
pgtool_load_config_file() {
    local config_file="${1:-}"
    local loaded=false

    # 按优先级搜索配置文件
    local -a config_paths=()

    # 1. 显式指定的配置文件
    if [[ -n "$config_file" ]]; then
        config_paths+=("$config_file")
    fi

    # 2. 环境变量指定的配置文件
    if [[ -n "${PGTOOL_CONFIG:-}" ]]; then
        config_paths+=("$PGTOOL_CONFIG")
    fi

    # 3. 当前目录配置文件
    config_paths+=("./.pgtool.conf")

    # 4. 用户配置文件
    config_paths+=("$HOME/.config/pgtool/pgtool.conf")
    config_paths+=("$HOME/.pgtool.conf")

    # 5. 系统配置文件
    config_paths+=("/etc/pgtool/pgtool.conf")

    # 尝试加载
    local path
    for path in "${config_paths[@]}"; do
        if [[ -f "$path" ]] && [[ -r "$path" ]]; then
            pgtool_debug "加载配置文件: $path"
            # shellcheck source=/dev/null
            source "$path"
            PGTOOL_CONFIG_FILE="$path"
            loaded=true
            break
        fi
    done

    if [[ "$loaded" == false ]]; then
        pgtool_debug "未找到配置文件，使用默认配置"
    fi
}

#==============================================================================
# 主函数
#==============================================================================

main() {
    # 重新初始化（以应用可能的配置）
    pgtool_init

    # 解析全局选项
    local -a remaining_args=()

    # 检查是否为命令组帮助模式（如: pgtool check --help）
    local cmd_group=""
    local is_group_help=false
    if [[ $# -ge 2 ]]; then
        case "$1" in
            check|stat|admin|analyze|monitor|plugin)
                cmd_group="$1"
                if [[ "$2" == "--help" ]] || [[ "$2" == "-h" ]]; then
                    is_group_help=true
                fi
                ;;
        esac
    fi

    # 如果不是命令组帮助，解析全局选项
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                # 只有在没有剩余参数时才显示全局帮助
                if [[ ${#remaining_args[@]} -eq 0 && -z "$cmd_group" ]]; then
                    pgtool_global_help
                    return $EXIT_SUCCESS
                fi
                # 否则将 --help 传递给子命令
                remaining_args+=("$1")
                shift
                ;;
            -v|--version)
                pgtool_version
                return $EXIT_SUCCESS
                ;;
            -c=*|--config=*)
                PGTOOL_CONFIG_FILE="${1#*=}"
                shift
                ;;
            -c|--config)
                shift
                PGTOOL_CONFIG_FILE="${1:-}"
                if [[ -z "$PGTOOL_CONFIG_FILE" ]]; then
                    pgtool_fatal "--config 需要参数"
                fi
                shift
                ;;
            --format=*)
                PGTOOL_FORMAT="${1#*=}"
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
            --timeout=*)
                PGTOOL_TIMEOUT="${1#*=}"
                if ! is_int "$PGTOOL_TIMEOUT"; then
                    pgtool_fatal "--timeout 必须是整数"
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
            --color=*)
                PGTOOL_COLOR="${1#*=}"
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
            --log-level=*)
                PGTOOL_LOG_LEVEL="${1#*=}"
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
            --host=*)
                PGTOOL_HOST="${1#*=}"
                export PGHOST="$PGTOOL_HOST"
                shift
                ;;
            --host)
                shift
                PGTOOL_HOST="${1:-}"
                export PGHOST="$PGTOOL_HOST"
                shift
                ;;
            --port=*)
                PGTOOL_PORT="${1#*=}"
                export PGPORT="$PGTOOL_PORT"
                shift
                ;;
            --port)
                shift
                PGTOOL_PORT="${1:-}"
                export PGPORT="$PGTOOL_PORT"
                shift
                ;;
            --user=*|--username=*)
                PGTOOL_USER="${1#*=}"
                export PGUSER="$PGTOOL_USER"
                shift
                ;;
            --user|--username)
                shift
                PGTOOL_USER="${1:-}"
                export PGUSER="$PGTOOL_USER"
                shift
                ;;
            --dbname=*|--database=*)
                PGTOOL_DATABASE="${1#*=}"
                export PGDATABASE="$PGTOOL_DATABASE"
                shift
                ;;
            --dbname|--database)
                shift
                PGTOOL_DATABASE="${1:-}"
                export PGDATABASE="$PGTOOL_DATABASE"
                shift
                ;;
            --password)
                shift
                export PGPASSWORD="${1:-}"
                shift
                ;;
            --no-password)
                export PGPASSWORD=""
                shift
                ;;
            -w|--no-password)
                export PGPASSWORD=""
                shift
                ;;
            -W|--password)
                # 交互式输入密码，psql 会处理
                shift
                ;;
            --)
                shift
                remaining_args+=("$@")
                break
                ;;
            -*)
                # 如果已经有命令组，将选项传递给子命令
                if [[ ${#remaining_args[@]} -gt 0 ]]; then
                    remaining_args+=("$1")
                    shift
                else
                    pgtool_fatal "未知选项: $1 (使用 --help 查看帮助)"
                fi
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done

    # 加载配置文件
    pgtool_load_config_file "${PGTOOL_CONFIG_FILE:-}"

    # 重新初始化连接（配置可能已更改）
    pgtool_pg_init

    # 加载插件
    pgtool_load_plugins

    # 分发命令
    if [[ ${#remaining_args[@]} -eq 0 ]]; then
        pgtool_global_help
        return $EXIT_SUCCESS
    fi

    pgtool_dispatch "${remaining_args[@]}"
}

#==============================================================================
# 执行
#==============================================================================

# 捕获中断信号
trap 'echo; pgtool_info "操作已取消"; exit $EXIT_INTERRUPT' INT TERM

# 运行主函数
main "$@"
