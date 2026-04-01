#!/bin/bash
# lib/plugin.sh - 插件管理器

# 必须先加载 core.sh 和 log.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# 插件目录
#==============================================================================

PGTOOL_PLUGINS_DIR="${PGTOOL_PLUGINS_DIR:-$PGTOOL_ROOT/plugins}"

#==============================================================================
# 插件加载
#==============================================================================

# 加载所有插件
pgtool_load_plugins() {
    if [[ ! -d "$PGTOOL_PLUGINS_DIR" ]]; then
        pgtool_debug "插件目录不存在: $PGTOOL_PLUGINS_DIR"
        return 0
    fi

    pgtool_debug "扫描插件目录: $PGTOOL_PLUGINS_DIR"

    local plugin_dir
    for plugin_dir in "$PGTOOL_PLUGINS_DIR"/*/; do
        # 防止无匹配时返回目录本身
        [[ -d "$plugin_dir" ]] || continue

        pgtool_load_plugin "$plugin_dir"
    done
}

# 加载单个插件
pgtool_load_plugin() {
    local plugin_dir="$1"
    local plugin_name
    plugin_name=$(basename "$plugin_dir")

    pgtool_debug "加载插件: $plugin_name"

    # 检查配置文件
    local config_file="$plugin_dir/plugin.conf"
    if [[ ! -f "$config_file" ]]; then
        pgtool_warn "插件 $plugin_name 缺少配置文件"
        return 1
    fi

    # 读取配置
    local PLUGIN_NAME=""
    local PLUGIN_VERSION=""
    local PLUGIN_DESCRIPTION=""
    local PLUGIN_DEPENDS=""
    local PLUGIN_COMMANDS=""

    source "$config_file"

    if [[ -z "$PLUGIN_NAME" ]]; then
        pgtool_warn "插件配置文件缺少 PLUGIN_NAME: $config_file"
        return 1
    fi

    # 检查依赖
    if ! pgtool_check_plugin_deps "$PLUGIN_DEPENDS"; then
        pgtool_warn "插件 $PLUGIN_NAME 依赖检查失败"
        return 1
    fi

    # 加载命令
    local cmd_dir="$plugin_dir/commands"
    if [[ -d "$cmd_dir" ]]; then
        local cmd_file
        for cmd_file in "$cmd_dir"/*.sh; do
            [[ -f "$cmd_file" ]] || continue
            pgtool_debug "加载插件命令: $cmd_file"
            # shellcheck source=/dev/null
            source "$cmd_file"
        done
    fi

    # 注册命令
    if [[ -n "$PLUGIN_COMMANDS" ]]; then
        pgtool_register_plugin_commands "$PLUGIN_NAME" "$PLUGIN_COMMANDS"
    fi

    pgtool_debug "插件加载成功: $PLUGIN_NAME v$PLUGIN_VERSION"
}

# 检查插件依赖
pgtool_check_plugin_deps() {
    local deps="$1"

    if [[ -z "$deps" ]]; then
        return 0
    fi

    local dep
    IFS=',' read -ra DEPS <<< "$deps"
    for dep in "${DEPS[@]}"; do
        dep=$(trim "$dep")
        if ! pgtool_check_single_dep "$dep"; then
            return 1
        fi
    done

    return 0
}

# 检查单个依赖
pgtool_check_single_dep() {
    local dep="$1"

    # 解析依赖格式: package>=version 或 package
    local package="${dep%%[>=<]*}"
    local operator=""
    local version=""

    if [[ "$dep" == *[\>=\<]* ]]; then
        if [[ "$dep" == *">="* ]]; then
            operator=">="
            version="${dep#*>=}"
        elif [[ "$dep" == *">"* ]]; then
            operator=">"
            version="${dep#*>}"
        elif [[ "$dep" == *"<="* ]]; then
            operator="<="
            version="${dep#*<=}"
        elif [[ "$dep" == *"<"* ]]; then
            operator="<"
            version="${dep#*<}"
        elif [[ "$dep" == *"="* ]]; then
            operator="="
            version="${dep#*=}"
        fi
    fi

    case "$package" in
        pgtool)
            if [[ -n "$version" ]]; then
                if ! pgtool_version_compare "$PGTOOL_VERSION" "$operator" "$version"; then
                    pgtool_warn "pgtool 版本不满足要求: $dep"
                    return 1
                fi
            fi
            ;;
        bash)
            local bash_version="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}"
            if [[ -n "$version" ]]; then
                if ! pgtool_version_compare "$bash_version" "$operator" "$version"; then
                    pgtool_warn "Bash 版本不满足要求: $dep"
                    return 1
                fi
            fi
            ;;
        psql)
            if ! command -v psql &>/dev/null; then
                pgtool_warn "未找到 psql"
                return 1
            fi
            ;;
        *)
            if ! command -v "$package" &>/dev/null; then
                pgtool_warn "未找到依赖: $package"
                return 1
            fi
            ;;
    esac

    return 0
}

# 版本比较
pgtool_version_compare() {
    local ver1="$1"
    local op="$2"
    local ver2="$3"

    # 将版本号转换为可比较的数值
    local num1
    local num2
    num1=$(pgtool_version_to_num "$ver1")
    num2=$(pgtool_version_to_num "$ver2")

    case "$op" in
        '='|'=='|eq)  [[ "$num1" -eq "$num2" ]] ;;
        '!='|ne)    [[ "$num1" -ne "$num2" ]] ;;
        '>'|gt)     [[ "$num1" -gt "$num2" ]] ;;
        '>='|ge)    [[ "$num1" -ge "$num2" ]] ;;
        '<'|lt)     [[ "$num1" -lt "$num2" ]] ;;
        '<='|le)    [[ "$num1" -le "$num2" ]] ;;
        *)          return 1 ;;
    esac
}

# 版本号转数值（简化版本）
pgtool_version_to_num() {
    local version="$1"
    local major
    local minor=0
    local patch=0

    major="${version%%.*}"
    local rest="${version#*.}"

    if [[ "$rest" != "$version" ]]; then
        minor="${rest%%.*}"
        rest="${rest#*.}"
        if [[ "$rest" != "$minor" ]]; then
            patch="${rest%%.*}"
        fi
    fi

    echo $((major * 10000 + minor * 100 + patch))
}

#==============================================================================
# 插件命令注册
#==============================================================================

# 注册插件命令
pgtool_register_plugin_commands() {
    local plugin_name="$1"
    local commands="$2"

    # 插件命令存储在环境变量中 (Bash 3.x 兼容)
    local var_name="PGTOOL_PLUGIN_${plugin_name}_COMMANDS"
    eval "export $var_name=\"$commands\""

    pgtool_debug "注册插件命令: $plugin_name -> $commands"
}

# 列出已加载的插件
pgtool_list_plugins() {
    local plugin_dir
    local count=0

    echo "已安装的插件:"

    for plugin_dir in "$PGTOOL_PLUGINS_DIR"/*/; do
        [[ -d "$plugin_dir" ]] || continue

        local plugin_name
        plugin_name=$(basename "$plugin_dir")
        local config_file="$plugin_dir/plugin.conf"

        if [[ -f "$config_file" ]]; then
            local PLUGIN_NAME=""
            local PLUGIN_VERSION=""
            local PLUGIN_DESCRIPTION=""

            source "$config_file"

            printf "  %-20s %-10s %s\n" "$PLUGIN_NAME" "v$PLUGIN_VERSION" "${PLUGIN_DESCRIPTION:0:40}"
            ((count++))
        fi
    done

    if [[ $count -eq 0 ]]; then
        echo "  (无)"
    fi
}

# 显示插件信息
pgtool_plugin_info() {
    local plugin_name="$1"
    local config_file="$PGTOOL_PLUGINS_DIR/$plugin_name/plugin.conf"

    if [[ ! -f "$config_file" ]]; then
        pgtool_error "未找到插件: $plugin_name"
        return 1
    fi

    local PLUGIN_NAME=""
    local PLUGIN_VERSION=""
    local PLUGIN_DESCRIPTION=""
    local PLUGIN_DEPENDS=""
    local PLUGIN_COMMANDS=""

    source "$config_file"

    pgtool_header "插件信息"
    pgtool_kv "名称" "$PLUGIN_NAME"
    pgtool_kv "版本" "$PLUGIN_VERSION"
    pgtool_kv "描述" "$PLUGIN_DESCRIPTION"
    pgtool_kv "依赖" "${PLUGIN_DEPENDS:-无}"
    pgtool_kv "命令" "${PLUGIN_COMMANDS:-无}"
}
