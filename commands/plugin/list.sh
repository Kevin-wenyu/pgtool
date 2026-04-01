#!/bin/bash
# commands/plugin/list.sh - 列出已安装插件

pgtool_plugin_list() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<EOF
列出已安装插件

显示所有已安装的插件及其基本信息。

用法: pgtool plugin list [选项]

选项:
  -h, --help    显示帮助

示例:
  pgtool plugin list
EOF
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    echo "已安装的插件:"
    echo ""

    local plugin_dir
    local count=0

    for plugin_dir in "$PGTOOL_PLUGINS_DIR"/*/; do
        [[ -d "$plugin_dir" ]] || continue

        local config_file="$plugin_dir/plugin.conf"
        if [[ -f "$config_file" ]]; then
            local PLUGIN_NAME=""
            local PLUGIN_VERSION=""
            local PLUGIN_DESCRIPTION=""
            local PLUGIN_AUTHOR=""
            local PLUGIN_COMMANDS=""

            source "$config_file"

            if [[ -n "$PLUGIN_NAME" ]]; then
                echo "  $PLUGIN_NAME"
                echo "    版本:     $PLUGIN_VERSION"
                echo "    描述:     $PLUGIN_DESCRIPTION"
                [[ -n "$PLUGIN_AUTHOR" ]] && echo "    作者:     $PLUGIN_AUTHOR"
                [[ -n "$PLUGIN_COMMANDS" ]] && echo "    命令:     $PLUGIN_COMMANDS"
                echo ""
                ((count++))
            fi
        fi
    done

    if [[ $count -eq 0 ]]; then
        echo "  (无)"
        echo ""
        echo "插件目录: $PGTOOL_PLUGINS_DIR"
        echo ""
        echo "创建插件的方法:"
        echo "  1. 复制示例插件: cp -r plugins/example ~/.pgtool/plugins/myplugin"
        echo "  2. 修改 plugin.conf"
        echo "  3. 添加命令到 commands/ 目录"
    else
        echo "共 $count 个插件"
    fi
}
