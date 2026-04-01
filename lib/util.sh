#!/bin/bash
# lib/util.sh - 通用工具函数

# 必须先加载 core.sh 和 log.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# 字符串处理
#==============================================================================

# 去除字符串两端空白
trim() {
    local str="$*"
    # 去除前端空白
    str="${str#"${str%%[![:space:]]*}"}"
    # 去除后端空白
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}

# 检查字符串是否为空或空白
is_blank() {
    [[ -z "$(trim "$*")" ]]
}

# 检查字符串是否包含子串
contains() {
    local str="$1"
    local substr="$2"
    [[ "$str" == *"$substr"* ]]
}

# 字符串转小写 (兼容 Bash 3.x)
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# 字符串转大写 (兼容 Bash 3.x)
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# 重复字符
repeat_char() {
    local char="$1"
    local count="$2"
    printf '%*s' "$count" '' | tr ' ' "$char"
}

#==============================================================================
# 数值比较
#==============================================================================

# 检查是否为整数
is_int() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

# 检查是否为正整数
is_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]
}

# 数值比较（支持大数）
num_compare() {
    local op="$1"
    local val1="$2"
    local val2="$3"

    case "$op" in
        -eq|--eq|'==')  [[ "$val1" -eq "$val2" ]] ;;
        -ne|--ne|'!=')  [[ "$val1" -ne "$val2" ]] ;;
        -lt|--lt|'<')   [[ "$val1" -lt "$val2" ]] ;;
        -le|--le|'<=')  [[ "$val1" -le "$val2" ]] ;;
        -gt|--gt|'>')   [[ "$val1" -gt "$val2" ]] ;;
        -ge|--ge|'>=')  [[ "$val1" -ge "$val2" ]] ;;
        *)            return 1 ;;
    esac
}

#==============================================================================
# 时间处理
#==============================================================================

# 获取当前时间戳（秒）
now() {
    date +%s
}

# 格式化时间
format_time() {
    local timestamp="${1:-$(now)}"
    local format="${2:-%Y-%m-%d %H:%M:%S}"
    date -d "@$timestamp" "+$format" 2>/dev/null || date -r "$timestamp" "+$format" 2>/dev/null
}

# 计算时间差（秒）
time_diff() {
    local start="$1"
    local end="${2:-$(now)}"
    echo $((end - start))
}

# 人性化时间显示
human_duration() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local mins=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [[ $days -gt 0 ]]; then
        printf "%dd %02dh %02dm" "$days" "$hours" "$mins"
    elif [[ $hours -gt 0 ]]; then
        printf "%dh %02dm %02ds" "$hours" "$mins" "$secs"
    elif [[ $mins -gt 0 ]]; then
        printf "%dm %02ds" "$mins" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

#==============================================================================
# 文件操作
#==============================================================================

# 检查文件是否存在且可读
is_readable() {
    [[ -r "$1" ]]
}

# 检查文件是否存在且可写
is_writable() {
    [[ -w "$1" ]]
}

# 安全创建临时文件
make_temp() {
    local prefix="${1:-pgtool}"
    local temp_file
    temp_file=$(mktemp -t "${prefix}.XXXXXX")
    echo "$temp_file"
}

# 安全创建临时目录
make_temp_dir() {
    local prefix="${1:-pgtool}"
    local temp_dir
    temp_dir=$(mktemp -d -t "${prefix}.XXXXXX")
    echo "$temp_dir"
}

# 读取文件第一行
read_first_line() {
    local file="$1"
    if [[ -r "$file" ]]; then
        head -n 1 "$file"
    fi
}

# 获取文件行数
line_count() {
    local file="$1"
    if [[ -r "$file" ]]; then
        wc -l < "$file" | tr -d ' '
    else
        echo 0
    fi
}

#==============================================================================
# 数组操作
#==============================================================================

# 检查数组是否包含元素
array_contains() {
    local element="$1"
    shift
    local arr=("$@")
    local item

    for item in "${arr[@]}"; do
        if [[ "$item" == "$element" ]]; then
            return 0
        fi
    done
    return 1
}

# 数组长度
array_length() {
    local arr=("$@")
    echo "${#arr[@]}"
}

# 连接数组为字符串
array_join() {
    local delimiter="$1"
    shift
    local arr=("$@")
    local IFS="$delimiter"
    echo "${arr[*]}"
}

#==============================================================================
# 用户交互
#==============================================================================

# 确认提示
confirm() {
    local message="${1:-确认执行此操作?}"
    local response

    while true; do
        read -r -p "$message [y/N]: " response
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
        case "$response" in
            y|yes)
                return 0
                ;;
            n|no|"")
                return 1
                ;;
            *)
                echo "请输入 y 或 n"
                ;;
        esac
    done
}

# 带超时提示的确认
confirm_with_timeout() {
    local message="${1:-确认执行此操作?}"
    local timeout="${2:-30}"
    local response

    read -r -t "$timeout" -p "$message [y/N] (timeout: ${timeout}s): " response || {
        echo "超时，操作取消"
        return 1
    }

    case "${response,,}" in
        y|yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 打印进度条
progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"

    if [[ $total -le 0 ]]; then
        return
    fi

    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    printf '\r['
    printf '%*s' "$filled" '' | tr ' ' '#'
    printf '%*s' "$empty" '' | tr ' ' '-'
    printf '] %3d%%' "$percentage"

    if [[ $current -ge $total ]]; then
        echo
    fi
}

#==============================================================================
# 系统检测
#==============================================================================

# 检测操作系统
detect_os() {
    local os
    os=$(uname -s)
    case "$os" in
        Linux)   echo "linux" ;;
        Darwin)  echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

# 检测终端宽度
terminal_width() {
    stty size 2>/dev/null | awk '{print $2}' || echo 80
}

# 检测终端高度
terminal_height() {
    stty size 2>/dev/null | awk '{print $1}' || echo 24
}

# 检查是否以 root 运行
is_root() {
    [[ $EUID -eq 0 ]]
}

# 获取当前用户名
current_user() {
    id -un
}
