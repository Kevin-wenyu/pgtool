#!/bin/bash
# commands/plugin/index.sh - plugin 命令组索引

# 动态生成命令列表
pgtool_plugin_build_commands() {
    local commands=""
    local plugin_dir

    for plugin_dir in "$PGTOOL_PLUGINS_DIR"/*/; do
        [[ -d "$plugin_dir" ]] || continue

        local config_file="$plugin_dir/plugin.conf"
        if [[ -f "$config_file" ]]; then
            local PLUGIN_NAME=""
            local PLUGIN_COMMANDS=""
            source "$config_file"

            if [[ -n "$PLUGIN_NAME" && -n "$PLUGIN_COMMANDS" ]]; then
                if [[ -n "$commands" ]]; then
                    commands="$commands,"
                fi
                commands="${commands}${PLUGIN_NAME}:${PLUGIN_COMMANDS}"
            fi
        fi
    done

    echo "$commands"
}

PGTOOL_PLUGIN_COMMANDS="list:列出已安装插件"

# 动态添加插件命令
for plugin_dir in "$PGTOOL_PLUGINS_DIR"/*/; do
    [[ -d "$plugin_dir" ]] || continue
    config_file="$plugin_dir/plugin.conf"
    if [[ -f "$config_file" ]]; then
        PLUGIN_NAME=""
        PLUGIN_DESCRIPTION=""
        source "$config_file"
        if [[ -n "$PLUGIN_NAME" ]]; then
            PGTOOL_PLUGIN_COMMANDS="$PGTOOL_PLUGIN_COMMANDS,$PLUGIN_NAME:调用 $PLUGIN_NAME 插件"
        fi
    fi
done

pgtool_plugin_help() {
    cat <<EOF
插件管理命令

可用命令:
  list              列出已安装插件

已加载的插件:
EOF

    # 显示已加载的插件
    local plugin_dir
    for plugin_dir in "$PGTOOL_PLUGINS_DIR"/*/; do
        [[ -d "$plugin_dir" ]] || continue
        local config_file="$plugin_dir/plugin.conf"
        if [[ -f "$config_file" ]]; then
            local PLUGIN_NAME=""
            local PLUGIN_VERSION=""
            local PLUGIN_DESCRIPTION=""
            source "$config_file"
            if [[ -n "$PLUGIN_NAME" ]]; then
                printf "  %-15s v%-8s %s\n" "$PLUGIN_NAME" "$PLUGIN_VERSION" "${PLUGIN_DESCRIPTION:0:40}"
            fi
        fi
    done

    cat <<EOF

使用 'pgtool plugin <插件名> <命令>' 调用插件命令

示例:
  pgtool plugin list
  pgtool plugin example hello
  pgtool plugin example version
EOF
}
