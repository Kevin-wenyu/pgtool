#!/bin/bash
# commands/backup/status.sh - 显示备份状态

#===============================================================================
# 备份工具检测
#===============================================================================

# 自动检测备份工具
pgtool_backup_detect_tool() {
    if command -v pgbackrest &>/dev/null; then
        echo "pgbackrest"
        return 0
    elif command -v barman &>/dev/null; then
        echo "barman"
        return 0
    fi
    return 1
}

# 备份工具未找到提示
pgtool_backup_tool_not_found() {
    pgtool_error "未检测到备份工具"
    pgtool_info "请安装 pgBackRest、Barman 或配置 pg_dump 备份脚本"
    pgtool_info "支持的备份工具:"
    pgtool_info "  - pgBackRest (https://pgbackrest.org/)"
    pgtool_info "  - Barman (https://www.pgbarman.org/)"
    pgtool_info "  - pg_dump (PostgreSQL 自带逻辑备份)"
}

#===============================================================================
# pgBackRest 状态
#===============================================================================

pgtool_backup_status_pgbackrest() {
    local stanza="${1:-}"

    pgtool_info "检测到备份工具: pgBackRest"
    echo ""

    # 检查 pgbackrest 是否已安装
    if ! command -v pgbackrest &>/dev/null; then
        pgtool_error "pgbackrest 命令未找到"
        return $EXIT_NOT_FOUND
    fi

    # 显示版本
    local version
    version=$(pgbackrest version 2>/dev/null || echo "未知")
    pgtool_kv "工具版本" "$version"
    echo ""

    # 如果没有指定 stanza，尝试自动检测
    if [[ -z "$stanza" ]]; then
        pgtool_info "尝试自动检测 stanza..."
        stanza=$(pgbackrest info --output=text 2>/dev/null | head -1 | awk '{print $1}')
        if [[ -n "$stanza" ]]; then
            pgtool_info "检测到 stanza: $stanza"
        else
            pgtool_warn "未检测到 stanza，使用默认配置"
            stanza="main"
        fi
    fi

    pgtool_section "备份信息 (Stanza: $stanza)"

    # 获取 pgbackrest 信息
    local info_output
    local has_jq=false

    if command -v jq &>/dev/null; then
        has_jq=true
    fi

    if $has_jq; then
        # 使用 JSON 格式输出并解析
        info_output=$(pgbackrest info --stanza="$stanza" --output=json 2>/dev/null)

        if [[ -z "$info_output" ]] || [[ "$info_output" == "[]" ]]; then
            pgtool_warn "未找到备份信息"
            return $EXIT_NOT_FOUND
        fi

        # 解析 JSON 输出
        echo "$info_output" | jq -r '.[] | "名称: \(.name)
状态: \(.status // "unknown")
数据库版本: \(.db[]?.version // "unknown")
"' 2>/dev/null

        # 列出备份
        echo ""
        echo "备份列表:"
        echo "$info_output" | jq -r '.[].db[]?.backup[]? |
            "  备份ID: \(.label // "unknown")
    类型: \(.type // "unknown")
    大小: \(.info.size // 0 | if . > 1073741824 then "\(. / 1073741824 | floor) GB" elif . > 1048576 then "\(. / 1048576 | floor) MB" else "\(. / 1024 | floor) KB" end)
    开始时间: \(.timestamp.start // "unknown")
    结束时间: \(.timestamp.stop // "unknown")"' 2>/dev/null

        # 显示 WAL 归档状态
        echo ""
        echo "WAL 归档状态:"
        echo "$info_output" | jq -r '.[].db[]?.archive[]? |
            "  数据库 ID: \(.id // "unknown")
    最小 WAL: \(.min // "unknown")
    最大 WAL: \(.max // "unknown")"' 2>/dev/null
    else
        # 使用文本格式输出
        info_output=$(pgbackrest info --stanza="$stanza" --output=text 2>/dev/null)

        if [[ -z "$info_output" ]]; then
            pgtool_warn "未找到备份信息 (建议安装 jq 以获得更好的输出)"
            return $EXIT_NOT_FOUND
        fi

        echo "$info_output"
    fi

    return $EXIT_SUCCESS
}

#===============================================================================
# Barman 状态
#===============================================================================

pgtool_backup_status_barman() {
    local server="${1:-}"

    pgtool_info "检测到备份工具: Barman"
    echo ""

    # 检查 barman 是否已安装
    if ! command -v barman &>/dev/null; then
        pgtool_error "barman 命令未找到"
        return $EXIT_NOT_FOUND
    fi

    # 显示版本
    local version
    version=$(barman version 2>/dev/null | head -1 || echo "未知")
    pgtool_kv "工具版本" "$version"
    echo ""

    # 如果没有指定 server，尝试自动检测
    if [[ -z "$server" ]]; then
        pgtool_info "尝试自动检测 server..."
        server=$(barman list-server 2>/dev/null | head -1 | awk '{print $1}')
        if [[ -n "$server" ]]; then
            pgtool_info "检测到 server: $server"
        else
            pgtool_warn "未检测到 server，显示所有服务器状态"
        fi
    fi

    pgtool_section "Barman 状态"

    if [[ -n "$server" ]]; then
        # 显示特定服务器状态
        local status_output
        status_output=$(barman status "$server" 2>/dev/null)

        if [[ -z "$status_output" ]]; then
            pgtool_warn "无法获取 server '$server' 的状态"
            return $EXIT_NOT_FOUND
        fi

        echo "$status_output"

        # 显示备份列表
        echo ""
        pgtool_section "备份列表 (Server: $server)"
        barman list-backup "$server" 2>/dev/null || pgtool_warn "无法获取备份列表"
    else
        # 显示所有服务器状态
        barman status 2>/dev/null || {
            pgtool_error "无法获取 Barman 状态"
            return $EXIT_GENERAL_ERROR
        }

        # 列出所有服务器
        echo ""
        pgtool_section "服务器列表"
        barman list-server 2>/dev/null || pgtool_warn "无法获取服务器列表"
    fi

    return $EXIT_SUCCESS
}

#===============================================================================
# pg_dump 状态
#===============================================================================

pgtool_backup_status_pg_dump() {
    pgtool_info "检测 pg_dump 逻辑备份..."
    echo ""

    # 常见的备份目录
    local -a backup_dirs=(
        "/var/lib/pgsql/backups"
        "/var/lib/postgresql/backups"
        "/opt/backups/postgresql"
        "/backup/postgresql"
        "/backups/postgresql"
        "$HOME/backups"
        "$HOME/postgresql/backups"
        "/tmp/postgresql_backups"
    )

    local found_backups=false
    local -a found_files=()

    pgtool_section "搜索备份文件"

    for dir in "${backup_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            pgtool_info "检查目录: $dir"

            # 搜索 .sql, .dump, .sql.gz, .dump.gz, .backup 文件
            while IFS= read -r -d '' file; do
                found_files+=("$file")
                found_backups=true
            done < <(find "$dir" -maxdepth 2 -type f \( \
                -name "*.sql" -o \
                -name "*.dump" -o \
                -name "*.sql.gz" -o \
                -name "*.dump.gz" -o \
                -name "*.backup" \
                \) -print0 2>/dev/null)
        fi
    done

    # 显示找到的备份
    if [[ "$found_backups" == true ]]; then
        echo ""
        echo "找到的备份文件:"
        echo ""

        # 表头
        printf "%-40s %-15s %-20s %s\n" "文件名" "大小" "修改时间" "类型"
        printf "%-40s %-15s %-20s %s\n" "--------" "----" "----------" "----"

        # 显示每个备份文件
        local file
        for file in "${found_files[@]:0:20}"; do
            local basename
            local size
            local mtime
            local ftype

            basename=$(basename "$file")
            size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
            mtime=$(stat -c "%y" "$file" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$file" 2>/dev/null)

            # 确定文件类型
            if [[ "$file" == *.sql* ]]; then
                ftype="SQL"
            elif [[ "$file" == *.dump* ]]; then
                ftype="Custom"
            elif [[ "$file" == *.backup* ]]; then
                ftype="Backup"
            else
                ftype="Unknown"
            fi

            # 截断文件名
            if [[ ${#basename} -gt 38 ]]; then
                basename="${basename:0:35}..."
            fi

            printf "%-40s %-15s %-20s %s\n" "$basename" "$size" "$mtime" "$ftype"
        done

        if [[ ${#found_files[@]} -gt 20 ]]; then
            echo ""
            pgtool_info "... 还有 $(( ${#found_files[@]} - 20 )) 个文件未显示"
        fi

        echo ""
        echo "总计找到 ${#found_files[@]} 个备份文件"
    else
        pgtool_warn "未找到 pg_dump 备份文件"
        pgtool_info "常见备份目录:"
        for dir in "${backup_dirs[@]}"; do
            pgtool_info "  - $dir"
        done
    fi

    # 显示 pg_dump 信息
    echo ""
    pgtool_section "pg_dump 信息"
    if command -v pg_dump &>/dev/null; then
        local pgdump_version
        pgdump_version=$(pg_dump --version 2>/dev/null)
        pgtool_kv "pg_dump 版本" "$pgdump_version"
    else
        pgtool_warn "pg_dump 未安装"
    fi

    return $EXIT_SUCCESS
}

#===============================================================================
# 主函数
#===============================================================================

pgtool_backup_status() {
    local tool=""
    local stanza=""
    local server=""
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_backup_status_help
                return 0
                ;;
            --tool)
                shift
                tool="$1"
                shift
                ;;
            --stanza)
                shift
                stanza="$1"
                shift
                ;;
            --server)
                shift
                server="$1"
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                # 全局选项，跳过参数值
                shift
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # 如果没有指定工具，尝试自动检测
    if [[ -z "$tool" ]]; then
        tool=$(pgtool_backup_detect_tool) || {
            pgtool_backup_tool_not_found
            return $EXIT_NOT_FOUND
        }
    fi

    # 转换工具名称为小写
    tool=$(echo "$tool" | tr '[:upper:]' '[:lower:]')

    # 根据工具分派到对应的函数
    case "$tool" in
        pgbackrest|pg_backrest)
            pgtool_backup_status_pgbackrest "$stanza"
            return $?
            ;;
        barman)
            pgtool_backup_status_barman "$server"
            return $?
            ;;
        pgdump|pg_dump|dump)
            pgtool_backup_status_pg_dump
            return $?
            ;;
        *)
            pgtool_error "未知的备份工具: $tool"
            pgtool_info "支持的备份工具: pgbackrest, barman, pg_dump"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

#===============================================================================
# 帮助函数
#===============================================================================

pgtool_backup_status_help() {
    cat <<EOF
显示备份状态

显示 PostgreSQL 备份系统的状态，包括：
- 备份工具版本和配置
- 最近的备份列表
- 备份大小和时间
- WAL 归档状态 (pgBackRest/Barman)
- 本地 pg_dump 备份文件

用法: pgtool backup status [选项]

选项:
  -h, --help              显示帮助
      --tool TOOL         指定备份工具 (pgbackrest|barman|pg_dump)
      --stanza NAME       pgBackRest: 指定 stanza 名称
      --server NAME       Barman: 指定服务器名称
      --format FORMAT     输出格式 (table|json|csv|tsv)

自动检测:
  如果未指定 --tool，pgtool 会自动检测已安装的备份工具
  检测顺序: pgBackRest > Barman > pg_dump

输出内容:
  pgBackRest:
    - 工具版本
    - Stanza 配置
    - 备份历史 (全量/增量)
    - 备份大小
    - WAL 归档状态

  Barman:
    - 工具版本
    - 服务器状态
    - 备份列表
    - 归档状态

  pg_dump:
    - 搜索常见备份目录
    - 列出找到的备份文件
    - 显示文件大小和修改时间

示例:
  # 自动检测备份工具
  pgtool backup status

  # 使用特定工具
  pgtool backup status --tool=pgbackrest
  pgtool backup status --tool=barman --server=prod

  # 指定 pgBackRest stanza
  pgtool backup status --stanza=mydb

  # JSON 输出
  pgtool backup status --format=json

依赖:
  - pgBackRest: 需要安装 pgbackrest 命令
  - Barman: 需要安装 barman 命令
  - jq: 可选，用于解析 pgBackRest JSON 输出
EOF
}
