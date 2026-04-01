#!/bin/bash
# plugins/example/commands/version.sh - 插件版本命令

pgtool_example_version() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<EOF
显示插件版本

用法: pgtool example version [选项]

选项:
  -h, --help    显示帮助
EOF
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    echo "Plugin: $PLUGIN_NAME"
    echo "Version: $PLUGIN_VERSION"
    echo "Description: $PLUGIN_DESCRIPTION"
    echo "Author: $PLUGIN_AUTHOR"
    if [[ -n "$PLUGIN_URL" ]]; then
        echo "URL: $PLUGIN_URL"
    fi
}
