#!/bin/bash
# plugins/example/commands/hello.sh - 示例命令

# 显示问候语的命令
pgtool_example_hello() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<EOF
显示问候语

用法: pgtool example hello [选项]

选项:
  -h, --help    显示帮助
  --name NAME   指定问候对象

示例:
  pgtool example hello
  pgtool example hello --name=World
EOF
                return 0
                ;;
            --name)
                shift
                local name="$1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    echo "${PLUGIN_EXAMPLE_GREETING:-Hello!}"
    if [[ -n "${name:-}" ]]; then
        echo "Nice to meet you, $name!"
    fi
}

# 注册帮助函数
pgtool_example_hello_help() {
    cat <<EOF
显示问候语 - 示例插件命令

这是一个演示用的简单命令。

用法: pgtool example hello [选项]

选项:
  -h, --help    显示帮助
  --name NAME   指定问候对象
EOF
}
