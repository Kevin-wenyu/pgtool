#!/bin/bash
# install.sh - pgtool 安装脚本

set -euo pipefail

# 版本
PGTOOL_VERSION="0.3.0"

# 安装路径
INSTALL_PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="$INSTALL_PREFIX/bin"
SHARE_DIR="$INSTALL_PREFIX/share/pgtool"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 输出函数
info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# 检查依赖
check_deps() {
    local missing=()

    if ! command -v bash &>/dev/null; then
        missing+=("bash")
    fi

    if ! command -v psql &>/dev/null; then
        missing+=("psql (postgresql-client)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "缺少依赖: ${missing[*]}"
        exit 1
    fi

    info "依赖检查通过"
}

# 检查 bash 版本
check_bash_version() {
    local version
    version="${BASH_VERSINFO[0]}"

    if [[ $version -lt 3 ]]; then
        error "需要 Bash 3.0 或更高版本"
        exit 1
    fi

    if [[ $version -lt 4 ]]; then
        warn "Bash 版本 $version，某些高级功能受限"
    fi
}

# 安装文件
install_files() {
    local src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    info "安装路径: $INSTALL_PREFIX"

    # 创建目录
    mkdir -p "$BIN_DIR"
    mkdir -p "$SHARE_DIR"
    mkdir -p "$SHARE_DIR/lib"
    mkdir -p "$SHARE_DIR/commands"
    mkdir -p "$SHARE_DIR/sql"

    # 复制主脚本
    info "复制主程序..."
    cp "$src_dir/pgtool.sh" "$SHARE_DIR/"
    chmod +x "$SHARE_DIR/pgtool.sh"

    # 复制库文件
    info "复制库文件..."
    cp -r "$src_dir/lib/"* "$SHARE_DIR/lib/"

    # 复制命令
    info "复制命令..."
    cp -r "$src_dir/commands/"* "$SHARE_DIR/commands/"

    # 复制 SQL 文件
    info "复制 SQL 文件..."
    cp -r "$src_dir/sql/"* "$SHARE_DIR/sql/"

    # 创建软链接
    info "创建软链接..."
    ln -sf "$SHARE_DIR/pgtool.sh" "$BIN_DIR/pgtool"

    info "安装完成!"
}

# 创建配置文件示例
install_config() {
    local config_dir="$HOME/.config/pgtool"

    if [[ ! -d "$config_dir" ]]; then
        info "创建配置目录: $config_dir"
        mkdir -p "$config_dir"
    fi

    if [[ ! -f "$config_dir/pgtool.conf" ]]; then
        info "复制配置文件示例..."
        cp "$(dirname "${BASH_SOURCE[0]}")/conf/pgtool.conf" "$config_dir/"
    fi
}

# 显示使用说明
show_usage() {
    echo ""
    echo "======================================="
    echo "pgtool v$PGTOOL_VERSION 安装成功!"
    echo "======================================="
    echo ""
    echo "使用方法:"
    echo "  pgtool --help              显示帮助"
    echo "  pgtool check xid           检查 XID 年龄"
    echo "  pgtool stat activity       查看活动会话"
    echo ""
    echo "配置文件: ~/.config/pgtool/pgtool.conf"
    echo ""
    echo "卸载方法:"
    echo "  rm -rf $SHARE_DIR"
    echo "  rm -f $BIN_DIR/pgtool"
    echo "======================================="
}

# 主函数
main() {
    echo "pgtool v$PGTOOL_VERSION 安装程序"
    echo "======================================="
    echo ""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)
                shift
                INSTALL_PREFIX="$1"
                BIN_DIR="$INSTALL_PREFIX/bin"
                SHARE_DIR="$INSTALL_PREFIX/share/pgtool"
                ;;
            --help|-h)
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  --prefix DIR    安装到指定目录 (默认: /usr/local)"
                echo "  --help, -h      显示帮助"
                exit 0
                ;;
            *)
                error "未知选项: $1"
                exit 1
                ;;
        esac
        shift
    done

    check_deps
    check_bash_version
    install_files
    install_config
    show_usage
}

main "$@"
