#!/bin/bash
# commands/plugin/example.sh - 调用 example 插件

pgtool_plugin_example() {
    local cmd="${1:-}"
    shift || true

    if [[ -z "$cmd" ]]; then
        echo "用法: pgtool plugin example <命令> [选项]"
        echo ""
        echo "可用命令:"
        echo "  hello     显示问候语"
        echo "  version   显示插件版本"
        echo ""
        echo "示例:"
        echo "  pgtool plugin example hello"
        echo "  pgtool plugin example hello --name=World"
        return 0
    fi

    # 检查命令是否存在
    local cmd_file="$PGTOOL_PLUGINS_DIR/example/commands/${cmd}.sh"
    if [[ ! -f "$cmd_file" ]]; then
        pgtool_error "未知命令: $cmd"
        return 1
    fi

    # 加载插件配置
    local config_file="$PGTOOL_PLUGINS_DIR/example/plugin.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    fi

    # 加载命令
    source "$cmd_file"

    # 执行命令
    local func_name="pgtool_example_${cmd}"
    if type "$func_name" &>/dev/null; then
        "$func_name" "$@"
    else
        pgtool_error "命令函数未定义: $func_name"
        return 1
    fi
}
