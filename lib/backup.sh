#!/bin/bash
# lib/backup.sh - 备份工具集成库 (pgBackRest/Barman)

# 必须先加载 core.sh 和 log.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# 工具检测
#==============================================================================

# 自动检测可用的备份工具
# 返回: pgbackrest|barman|none
pgtool_backup_detect_tool() {
    if pgtool_backup_pgbackrest_check; then
        echo "pgbackrest"
        return 0
    elif pgtool_backup_barman_check; then
        echo "barman"
        return 0
    else
        echo "none"
        return 1
    fi
}

# 检查 pgBackRest 是否已安装
pgtool_backup_pgbackrest_check() {
    command -v pgbackrest &>/dev/null
}

# 检查 Barman 是否已安装
pgtool_backup_barman_check() {
    command -v barman &>/dev/null
}

# 获取 pgBackRest 版本
pgtool_backup_pgbackrest_version() {
    if ! pgtool_backup_pgbackrest_check; then
        return 1
    fi

    pgbackrest version 2>/dev/null | head -n 1
}

# 获取 Barman 版本
pgtool_backup_barman_version() {
    if ! pgtool_backup_barman_check; then
        return 1
    fi

    barman version 2>/dev/null | head -n 1
}

#==============================================================================
# pgBackRest 集成
#==============================================================================

# 列出 pgBackRest 所有 stanza
pgtool_backup_pgbackrest_list_stanza() {
    if ! pgtool_backup_pgbackrest_check; then
        pgtool_backup_tool_not_found "pgBackRest"
        return $EXIT_NOT_FOUND
    fi

    pgbackrest --output=text stanza-list 2>/dev/null
}

# 获取 pgBackRest stanza 详细信息 (JSON)
pgtool_backup_pgbackrest_info() {
    local stanza="${1:-}"

    if ! pgtool_backup_pgbackrest_check; then
        pgtool_backup_tool_not_found "pgBackRest"
        return $EXIT_NOT_FOUND
    fi

    local cmd=(pgbackrest --output=json info)
    [[ -n "$stanza" ]] && cmd+=(--stanza="$stanza")

    "${cmd[@]}" 2>/dev/null
}

# 获取 pgBackRest stanza 详细信息 (文本格式)
pgtool_backup_pgbackrest_info_text() {
    local stanza="${1:-}"

    if ! pgtool_backup_pgbackrest_check; then
        pgtool_backup_tool_not_found "pgBackRest"
        return $EXIT_NOT_FOUND
    fi

    local cmd=(pgbackrest --output=text info)
    [[ -n "$stanza" ]] && cmd+=(--stanza="$stanza")

    "${cmd[@]}" 2>/dev/null
}

# 运行 pgBackRest 验证
pgtool_backup_pgbackrest_verify() {
    local stanza="${1:-}"

    if ! pgtool_backup_pgbackrest_check; then
        pgtool_backup_tool_not_found "pgBackRest"
        return $EXIT_NOT_FOUND
    fi

    local cmd=(pgbackrest verify)
    [[ -n "$stanza" ]] && cmd+=(--stanza="$stanza")

    "${cmd[@]}" 2>/dev/null
}

# 检查 pgBackRest 配置
pgtool_backup_pgbackrest_check_config() {
    if ! pgtool_backup_pgbackrest_check; then
        pgtool_backup_tool_not_found "pgBackRest"
        return $EXIT_NOT_FOUND
    fi

    pgbackrest check 2>/dev/null
}

# 获取 pgBackRest 备份列表
pgtool_backup_pgbackrest_list() {
    local stanza="${1:-}"

    if ! pgtool_backup_pgbackrest_check; then
        pgtool_backup_tool_not_found "pgBackRest"
        return $EXIT_NOT_FOUND
    fi

    local cmd=(pgbackrest --output=text info)
    [[ -n "$stanza" ]] && cmd+=(--stanza="$stanza")

    "${cmd[@]}" 2>/dev/null
}

#==============================================================================
# Barman 集成
#==============================================================================

# 列出 Barman 管理的所有服务器
pgtool_backup_barman_list_servers() {
    if ! pgtool_backup_barman_check; then
        pgtool_backup_tool_not_found "Barman"
        return $EXIT_NOT_FOUND
    fi

    barman list-server 2>/dev/null
}

# 获取 Barman 服务器状态
pgtool_backup_barman_status() {
    local server="${1:-}"

    if ! pgtool_backup_barman_check; then
        pgtool_backup_tool_not_found "Barman"
        return $EXIT_NOT_FOUND
    fi

    if [[ -n "$server" ]]; then
        barman status "$server" 2>/dev/null
    else
        barman status 2>/dev/null
    fi
}

# 列出 Barman 备份
pgtool_backup_barman_list() {
    local server="${1:-}"

    if ! pgtool_backup_barman_check; then
        pgtool_backup_tool_not_found "Barman"
        return $EXIT_NOT_FOUND
    fi

    if [[ -n "$server" ]]; then
        barman list-backup "$server" 2>/dev/null
    else
        barman list-backup 2>/dev/null
    fi
}

# 检查 Barman 服务器
pgtool_backup_barman_check() {
    local server="${1:-}"

    if ! pgtool_backup_barman_check; then
        pgtool_backup_tool_not_found "Barman"
        return $EXIT_NOT_FOUND
    fi

    if [[ -n "$server" ]]; then
        barman check "$server" 2>/dev/null
    else
        barman check 2>/dev/null
    fi
}

# 获取 Barman 服务器详细信息
pgtool_backup_barman_show_server() {
    local server="${1:-}"

    if ! pgtool_backup_barman_check; then
        pgtool_backup_tool_not_found "Barman"
        return $EXIT_NOT_FOUND
    fi

    if [[ -n "$server" ]]; then
        barman show-server "$server" 2>/dev/null
    else
        barman show-server 2>/dev/null
    fi
}

#==============================================================================
# WAL 归档检查
#==============================================================================

# 检查 WAL 归档是否已配置
pgtool_backup_archive_configured() {
    local result
    result=$(pgtool_pg_query_one "SELECT COALESCE(archive_mode, 'off') FROM pg_settings WHERE name = 'archive_mode'" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        return $EXIT_CONNECTION_ERROR
    fi

    [[ "$result" == "on" ]] || [[ "$result" == "always" ]]
}

# 获取 archive_command 配置
pgtool_backup_archive_command() {
    pgtool_pg_query_one "SELECT COALESCE(archive_command, '') FROM pg_settings WHERE name = 'archive_command'" 2>/dev/null
}

# 获取 archive_mode 配置
pgtool_backup_archive_mode() {
    pgtool_pg_query_one "SELECT COALESCE(archive_mode, 'off') FROM pg_settings WHERE name = 'archive_mode'" 2>/dev/null
}

# 检查是否使用 pgBackRest 进行归档
pgtool_backup_using_pgbackrest_archive() {
    local cmd
    cmd=$(pgtool_backup_archive_command)

    [[ "$cmd" == *"pgbackrest"* ]] || [[ "$cmd" == *"archive-push"* ]]
}

# 检查是否使用 Barman 进行归档
pgtool_backup_using_barman_archive() {
    local cmd
    cmd=$(pgtool_backup_archive_command)

    [[ "$cmd" == *"barman"* ]]
}

#==============================================================================
# 状态格式化输出
#==============================================================================

# 格式化备份工具状态输出
pgtool_backup_format_status() {
    local tool="$1"
    local status="$2"
    local details="${3:-}"

    echo "备份工具: $tool"
    echo "状态: $(pgtool_status "$status" "$status")"
    if [[ -n "$details" ]]; then
        echo "详情: $details"
    fi
}

# 格式化备份列表输出
pgtool_backup_format_list() {
    local tool="$1"
    shift
    local backups=("$@")

    pgtool_header "$tool 备份列表"

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "无备份记录"
        return 0
    fi

    local i=1
    for backup in "${backups[@]}"; do
        echo "  $i. $backup"
        i=$((i+1))
    done
}

# 格式化 pgBackRest 状态
pgtool_backup_format_pgbackrest_status() {
    local json_data="$1"

    if [[ -z "$json_data" ]]; then
        echo "无 pgBackRest 数据"
        return 1
    fi

    # 如果有 jq，使用 jq 解析
    if command -v jq &>/dev/null; then
        echo "$json_data" | jq -r '.[] | "Stanza: \(.name)"' 2>/dev/null
    else
        # 简单文本输出
        echo "$json_data"
    fi
}

# 格式化 Barman 状态
pgtool_backup_format_barman_status() {
    local status_data="$1"

    if [[ -z "$status_data" ]]; then
        echo "无 Barman 状态数据"
        return 1
    fi

    echo "$status_data"
}

# 工具未找到错误消息
pgtool_backup_tool_not_found() {
    local tool="${1:-备份工具}"

    pgtool_error "$tool 未安装或不在 PATH 中"
    pgtool_info "请安装 $tool 后重试"
}

#==============================================================================
# 备份配置检查
#==============================================================================

# 综合备份状态检查
pgtool_backup_status() {
    local format="${1:-text}"

    local tool detected_tool="none"
    local archive_enabled=false
    local archive_cmd=""
    local backup_info=""

    # 检测备份工具
    detected_tool=$(pgtool_backup_detect_tool) || true

    # 检查归档配置
    if pgtool_backup_archive_configured 2>/dev/null; then
        archive_enabled=true
        archive_cmd=$(pgtool_backup_archive_command 2>/dev/null || echo "")
    fi

    # 根据格式输出
    case "$format" in
        json)
            local archive_status="disabled"
            $archive_enabled && archive_status="enabled"

            echo "{"
            echo "  \"tool\": \"$detected_tool\","
            echo "  \"archive_enabled\": $archive_enabled,"
            echo "  \"archive_command\": \"$archive_cmd\","
            echo "  \"pgbackrest_available\": $(pgtool_backup_pgbackrest_check && echo "true" || echo "false"),"
            echo "  \"barman_available\": $(pgtool_backup_barman_check && echo "true" || echo "false")"
            echo "}"
            ;;
        *)
            pgtool_header "备份状态检查"
            echo
            pgtool_kv "检测到的工具" "$detected_tool"
            pgtool_kv "归档模式" "$($archive_enabled && pgtool_green "enabled" || pgtool_red "disabled")"
            if $archive_enabled; then
                pgtool_kv "归档命令" "$archive_cmd"
            fi
            echo
            pgtool_section "工具可用性"
            pgtool_kv "pgBackRest" "$(pgtool_backup_pgbackrest_check && pgtool_green "available" || pgtool_gray "not installed")"
            pgtool_kv "Barman" "$(pgtool_backup_barman_check && pgtool_green "available" || pgtool_gray "not installed")"
            ;;
    esac
}
