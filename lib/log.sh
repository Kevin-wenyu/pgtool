#!/bin/bash
# lib/log.sh - 日志系统

# 必须先加载 core.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# 日志级别管理
#==============================================================================

# 将日志级别名称转换为数值
pgtool_log_level_value() {
    local level
    level=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    case "$level" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        FATAL) echo $LOG_LEVEL_FATAL ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

# 获取当前日志级别数值
pgtool_current_log_level() {
    pgtool_log_level_value "$PGTOOL_LOG_LEVEL"
}

# 检查是否应该记录某级别的日志
pgtool_should_log() {
    local target_level="$1"
    local current_level
    current_level=$(pgtool_current_log_level)
    local target_value
    target_value=$(pgtool_log_level_value "$target_level")

    [[ $target_value -ge $current_level ]]
}

#==============================================================================
# 颜色输出控制
#==============================================================================

# 检查是否应该使用颜色
pgtool_use_color() {
    case "$PGTOOL_COLOR" in
        never|no|false|0)
            return 1
            ;;
        always|yes|true|1)
            return 0
            ;;
        auto|*)
            # 检查是否终端
            [[ -t 1 ]] && return 0 || return 1
            ;;
    esac
}

# 包装文本为颜色（如果启用颜色）
pgtool_color() {
    local color="$1"
    local text="$2"

    if pgtool_use_color; then
        echo -e "${color}${text}${COLOR_RESET}"
    else
        echo "$text"
    fi
}

# 快捷颜色函数
pgtool_red()     { pgtool_color "$COLOR_RED" "$1"; }
pgtool_green()   { pgtool_color "$COLOR_GREEN" "$1"; }
pgtool_yellow()  { pgtool_color "$COLOR_YELLOW" "$1"; }
pgtool_blue()    { pgtool_color "$COLOR_BLUE" "$1"; }
pgtool_magenta() { pgtool_color "$COLOR_MAGENTA" "$1"; }
pgtool_cyan()    { pgtool_color "$COLOR_CYAN" "$1"; }
pgtool_gray()    { pgtool_color "$COLOR_GRAY" "$1"; }
pgtool_bold()    { pgtool_color "$COLOR_BOLD" "$1"; }

#==============================================================================
# 日志输出函数
#==============================================================================

# 基础日志函数
pgtool_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 检查是否应该记录
    if ! pgtool_should_log "$level"; then
        return 0
    fi

    # 格式化输出
    local prefix="[$timestamp] [$level]"

    case "$level" in
        DEBUG)
            echo "$prefix $message" >&2
            ;;
        INFO)
            echo "$prefix $message"
            ;;
        WARN)
            if pgtool_use_color; then
                echo -e "${COLOR_YELLOW}${prefix}${COLOR_RESET} $message" >&2
            else
                echo "$prefix $message" >&2
            fi
            ;;
        ERROR)
            if pgtool_use_color; then
                echo -e "${COLOR_RED}${prefix}${COLOR_RESET} $message" >&2
            else
                echo "$prefix $message" >&2
            fi
            ;;
        FATAL)
            if pgtool_use_color; then
                echo -e "${COLOR_BOLD}${COLOR_RED}${prefix}${COLOR_RESET} $message" >&2
            else
                echo "$prefix $message" >&2
            fi
            ;;
    esac
}

# 各级别快捷函数
pgtool_debug() { pgtool_log "DEBUG" "$@"; }
pgtool_info()  { pgtool_log "INFO" "$@"; }
pgtool_warn()  { pgtool_log "WARN" "$@"; }
pgtool_error() { pgtool_log "ERROR" "$@"; }
pgtool_fatal() {
    pgtool_log "FATAL" "$@"
    exit "$EXIT_GENERAL_ERROR"
}

#==============================================================================
# 状态输出
#==============================================================================

# 根据状态输出颜色
pgtool_status() {
    local status="$1"
    local message="${2:-$status}"
    local status_upper
    status_upper=$(echo "$status" | tr '[:lower:]' '[:upper:]')

    case "$status_upper" in
        OK|SUCCESS|PASS)
            pgtool_green "$message"
            ;;
        WARN|WARNING)
            pgtool_yellow "$message"
            ;;
        CRITICAL|ERROR|FAIL)
            pgtool_red "$message"
            ;;
        INFO|PENDING|UNKNOWN)
            pgtool_blue "$message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# 成功消息
pgtool_success() {
    pgtool_green "✓ $*"
}

# 错误消息（带图标）
pgtool_fail() {
    pgtool_red "✗ $*"
}

# 警告消息（带图标）
pgtool_warning() {
    pgtool_yellow "⚠ $*"
}

#==============================================================================
# 审计日志
#==============================================================================

# 审计日志文件路径（可通过环境变量配置）
PGTOOL_AUDIT_LOG="${PGTOOL_AUDIT_LOG:-}"

# 设置审计日志文件
pgtool_audit_set_file() {
    local log_file="$1"
    if [[ -n "$log_file" ]]; then
        local log_dir
        log_dir=$(dirname "$log_file")
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" 2>/dev/null || {
                pgtool_error "无法创建审计日志目录: $log_dir"
                return 1
            }
        fi
        if [[ -f "$log_file" && ! -w "$log_file" ]]; then
            pgtool_error "审计日志文件不可写: $log_file"
            return 1
        fi
        PGTOOL_AUDIT_LOG="$log_file"
    fi
}

# 记录审计日志
pgtool_audit_log() {
    local action="$1"
    local details="${2:-}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user_info="${USER:-unknown}@${HOSTNAME:-unknown}"
    local db_info="${PGTOOL_HOST:-}:${PGTOOL_PORT:-}/${PGTOOL_DATABASE:-}"

    local log_entry="[$timestamp] [AUDIT] user=$user_info db=$db_info action=$action"
    if [[ -n "$details" ]]; then
        log_entry="$log_entry details=$details"
    fi

    # 输出到控制台
    pgtool_log "INFO" "[AUDIT] $action"

    # 写入审计日志文件（如果配置了）
    if [[ -n "$PGTOOL_AUDIT_LOG" ]]; then
        echo "$log_entry" >> "$PGTOOL_AUDIT_LOG" 2>/dev/null || {
            pgtool_warn "无法写入审计日志: $PGTOOL_AUDIT_LOG"
        }
    fi
}

# 记录危险操作审计日志
pgtool_audit_admin() {
    local command="$1"
    shift
    local args="$*"
    pgtool_audit_log "ADMIN_COMMAND" "command=$command args=$args"
}
