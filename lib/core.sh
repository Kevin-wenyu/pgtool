#!/bin/bash
# lib/core.sh - 核心常量与初始化

set -euo pipefail

#==============================================================================
# 版本信息
#==============================================================================
readonly PGTOOL_VERSION="0.1.0"
readonly PGTOOL_NAME="pgtool"

#==============================================================================
# 退出码定义
#==============================================================================
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_ARGS=2
readonly EXIT_CONNECTION_ERROR=3
readonly EXIT_TIMEOUT=4
readonly EXIT_SQL_ERROR=5
readonly EXIT_NOT_FOUND=6
readonly EXIT_PERMISSION=7
readonly EXIT_INTERRUPT=130

#==============================================================================
# 默认值
#==============================================================================
readonly PGTOOL_DEFAULT_TIMEOUT=30
readonly PGTOOL_DEFAULT_FORMAT="table"
readonly PGTOOL_DEFAULT_LOG_LEVEL="INFO"
readonly PGTOOL_DEFAULT_COLOR="auto"

#==============================================================================
# 颜色代码
#==============================================================================
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_GRAY='\033[0;90m'
readonly COLOR_BOLD='\033[1m'

#==============================================================================
# 日志级别常量
#==============================================================================
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_FATAL=4

#==============================================================================
# 初始化函数
#==============================================================================

# 初始化运行时环境
pgtool_init() {
    # 设置严格模式（如果尚未设置）
    set -o errexit 2>/dev/null || true
    set -o nounset 2>/dev/null || true
    set -o pipefail 2>/dev/null || true

    # 计算并导出根目录
    if [[ -z "${PGTOOL_ROOT:-}" ]]; then
        PGTOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        export PGTOOL_ROOT
    fi

    # 导出配置目录
    PGTOOL_CONFIG_DIR="${PGTOOL_CONFIG_DIR:-$HOME/.config/pgtool}"
    export PGTOOL_CONFIG_DIR

    # 设置默认配置值
    PGTOOL_TIMEOUT="${PGTOOL_TIMEOUT:-$PGTOOL_DEFAULT_TIMEOUT}"
    PGTOOL_FORMAT="${PGTOOL_FORMAT:-$PGTOOL_DEFAULT_FORMAT}"
    PGTOOL_LOG_LEVEL="${PGTOOL_LOG_LEVEL:-$PGTOOL_DEFAULT_LOG_LEVEL}"
    PGTOOL_COLOR="${PGTOOL_COLOR:-$PGTOOL_DEFAULT_COLOR}"

    export PGTOOL_TIMEOUT PGTOOL_FORMAT PGTOOL_LOG_LEVEL PGTOOL_COLOR
}

# 验证环境
pgtool_validate_env() {
    # 检查必要的命令
    if ! command -v psql &>/dev/null; then
        echo "错误: 未找到 psql 命令，请安装 PostgreSQL 客户端" >&2
        exit $EXIT_GENERAL_ERROR
    fi

    # 检查 bash 版本
pgtool_validate_env() {
    # 检查必要的命令
    if ! command -v psql &>/dev/null; then
        echo "错误: 未找到 psql 命令，请安装 PostgreSQL 客户端" >&2
        exit $EXIT_GENERAL_ERROR
    fi

    # 检查 bash 版本 (需要 4.0+，但 3.2 也可基本运行)
    # macOS 默认是 3.2，部分功能受限
    if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
        echo "错误: 需要 Bash 3.0 或更高版本" >&2
        exit $EXIT_GENERAL_ERROR
    fi

    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        # Bash 3.x 警告：某些高级功能不可用
        export PGTOOL_BASH_OLD=1
    fi
}
}

# 清理函数
pgtool_cleanup() {
    # 清理临时文件
    if [[ -n "${PGTOOL_TEMP_FILES:-}" ]]; then
        # shellcheck disable=SC2086
        rm -f $PGTOOL_TEMP_FILES 2>/dev/null || true
    fi
}

# 设置退出时清理
trap pgtool_cleanup EXIT

# 初始化
pgtool_init
pgtool_validate_env
