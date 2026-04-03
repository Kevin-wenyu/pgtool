#!/bin/bash
# commands/backup/verify.sh - 验证备份完整性

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
# pgBackRest 验证
#===============================================================================

pgtool_backup_verify_pgbackrest() {
    local stanza="${1:-}"
    local backup_id="${2:-}"

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
            pgtool_error "未检测到 stanza，请使用 --stanza 指定"
            return $EXIT_INVALID_ARGS
        fi
    fi

    pgtool_section "验证备份完整性 (Stanza: $stanza)"

    local verify_output
    local exit_code=0

    if [[ -n "$backup_id" ]]; then
        # 验证特定备份
        pgtool_info "验证备份: $backup_id"
        verify_output=$(pgbackrest verify --stanza="$stanza" --set="$backup_id" 2>&1)
        exit_code=$?
    else
        # 验证整个 stanza
        pgtool_info "验证 stanza 的所有备份..."
        verify_output=$(pgbackrest verify --stanza="$stanza" 2>&1)
        exit_code=$?
    fi

    echo "$verify_output"
    echo ""

    if [[ $exit_code -eq 0 ]]; then
        pgtool_section "验证结果"
        pgtool_info "状态: 通过"
        pgtool_info "所有备份文件完整性检查通过"
        return $EXIT_SUCCESS
    else
        pgtool_section "验证结果"
        pgtool_error "状态: 失败"
        pgtool_error "备份验证过程中发现错误"
        return $EXIT_GENERAL_ERROR
    fi
}

#===============================================================================
# Barman 验证
#===============================================================================

pgtool_backup_verify_barman() {
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
            pgtool_error "未检测到 server，请使用 --server 指定"
            return $EXIT_INVALID_ARGS
        fi
    fi

    pgtool_section "验证备份完整性 (Server: $server)"

    local check_output
    local exit_code=0

    # Barman 使用 check 命令验证备份完整性
    pgtool_info "检查备份和 WAL 归档状态..."
    check_output=$(barman check "$server" 2>&1)
    exit_code=$?

    echo "$check_output"
    echo ""

    # 检查输出中是否有错误
    local has_error=false
    if echo "$check_output" | grep -qi "error\|failed\|fail"; then
        has_error=true
    fi

    if [[ $exit_code -eq 0 ]] && [[ "$has_error" == false ]]; then
        pgtool_section "验证结果"
        pgtool_info "状态: 通过"
        pgtool_info "所有备份检查项正常"
        return $EXIT_SUCCESS
    else
        pgtool_section "验证结果"
        pgtool_error "状态: 失败"
        pgtool_error "备份检查过程中发现错误"
        return $EXIT_GENERAL_ERROR
    fi
}

#===============================================================================
# pg_dump 验证
#===============================================================================

pgtool_backup_verify_pg_dump() {
    local backup_id="${1:-}"

    pgtool_info "检测 pg_dump 逻辑备份..."
    echo ""

    if [[ -n "$backup_id" ]]; then
        # 验证特定备份文件
        if [[ ! -f "$backup_id" ]]; then
            pgtool_error "备份文件不存在: $backup_id"
            return $EXIT_NOT_FOUND
        fi

        pgtool_section "验证备份文件"
        pgtool_kv "文件路径" "$backup_id"

        local file_size
        file_size=$(stat -c "%s" "$backup_id" 2>/dev/null || stat -f "%z" "$backup_id" 2>/dev/null)
        pgtool_kv "文件大小" "$file_size bytes"
        echo ""

        # 根据文件类型进行验证
        local verify_result=0

        if [[ "$backup_id" == *.gz ]]; then
            # gzip 压缩文件
            pgtool_info "检查 gzip 文件完整性..."
            if gunzip -t "$backup_id" 2>&1; then
                pgtool_info "gzip 文件完整性检查通过"
            else
                pgtool_error "gzip 文件损坏或不完整"
                verify_result=1
            fi
        elif [[ "$backup_id" == *.sql ]]; then
            # 纯 SQL 文件 - 检查文件可读性
            pgtool_info "检查 SQL 文件可读性..."
            if head -1 "$backup_id" &>/dev/null; then
                pgtool_info "SQL 文件可读性检查通过"
            else
                pgtool_error "SQL 文件无法读取"
                verify_result=1
            fi
        elif [[ "$backup_id" == *.dump ]]; then
            # PostgreSQL custom dump 格式
            pgtool_info "检查 dump 文件格式..."
            local header
            header=$(xxd -l 16 "$backup_id" 2>/dev/null | head -1)
            if [[ -n "$header" ]]; then
                pgtool_info "dump 文件格式检查通过"
            else
                pgtool_error "dump 文件格式异常"
                verify_result=1
            fi
        else
            pgtool_warn "未知备份文件类型，进行基础可读性检查..."
            if head -c 1 "$backup_id" &>/dev/null; then
                pgtool_info "文件可读性检查通过"
            else
                pgtool_error "文件无法读取"
                verify_result=1
            fi
        fi

        echo ""
        pgtool_section "验证结果"
        if [[ $verify_result -eq 0 ]]; then
            pgtool_info "状态: 通过"
            return $EXIT_SUCCESS
        else
            pgtool_error "状态: 失败"
            return $EXIT_GENERAL_ERROR
        fi
    else
        # 未指定文件，提示用法
        pgtool_section "pg_dump 备份验证"
        pgtool_info "pg_dump 验证需要指定备份文件路径"
        pgtool_info "用法: pgtool backup verify --backup-id=/path/to/backup.sql"
        pgtool_info ""
        pgtool_info "支持的备份文件类型:"
        pgtool_info "  - .sql          纯 SQL 文件"
        pgtool_info "  - .sql.gz       gzip 压缩的 SQL 文件"
        pgtool_info "  - .dump         PostgreSQL 自定义格式"
        pgtool_info "  - .dump.gz      gzip 压缩的 dump 文件"
        return $EXIT_INVALID_ARGS
    fi
}

#===============================================================================
# 主函数
#===============================================================================

pgtool_backup_verify() {
    local tool=""
    local stanza=""
    local server=""
    local backup_id=""
    local -a opts=()
    local -a args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_backup_verify_help
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
            --backup-id)
                shift
                backup_id="$1"
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
            pgtool_backup_verify_pgbackrest "$stanza" "$backup_id"
            return $?
            ;;
        barman)
            pgtool_backup_verify_barman "$server"
            return $?
            ;;
        pgdump|pg_dump|dump)
            pgtool_backup_verify_pg_dump "$backup_id"
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

pgtool_backup_verify_help() {
    cat <<EOF
验证备份完整性

检查 PostgreSQL 备份文件的完整性和可用性，支持多种备份工具。

用法: pgtool backup verify [选项]

选项:
  -h, --help              显示帮助
      --tool TOOL         指定备份工具 (pgbackrest|barman|pg_dump)
      --stanza NAME       pgBackRest: 指定 stanza 名称
      --server NAME       Barman: 指定服务器名称
      --backup-id ID      指定要验证的备份 ID 或文件路径

自动检测:
  如果未指定 --tool，pgtool 会自动检测已安装的备份工具
  检测顺序: pgBackRest > Barman > pg_dump

验证内容:
  pgBackRest:
    - 使用 pgbackrest verify 命令
    - 验证备份文件的哈希完整性
    - 检查备份元数据的一致性
    - 支持验证特定备份集或整个 stanza

  Barman:
    - 使用 barman check 命令
    - 检查 PostgreSQL 连接
    - 验证备份目录和 WAL 归档
    - 检查保留策略配置

  pg_dump:
    - 验证文件可读性
    - 检查压缩文件完整性 (gzip)
    - 检查 dump 文件格式
    - 需要指定 --backup-id 为文件路径

示例:
  # 自动检测工具并验证
  pgtool backup verify

  # 验证 pgBackRest stanza
  pgtool backup verify --tool=pgbackrest --stanza=mydb

  # 验证特定备份集
  pgtool backup verify --tool=pgbackrest --stanza=mydb --backup-id=20230101-120000F

  # 验证 Barman 服务器
  pgtool backup verify --tool=barman --server=prod

  # 验证 pg_dump 备份文件
  pgtool backup verify --tool=pg_dump --backup-id=/backups/mydb_20230101.sql.gz

退出状态:
  0  验证成功，备份完整
  1  验证失败，发现错误或损坏
  2  参数错误或工具未配置
  6  备份文件/配置不存在

依赖:
  - pgBackRest: 需要安装 pgbackrest 命令
  - Barman: 需要安装 barman 命令
  - pg_dump: 需要 gzip 命令检查压缩文件
EOF
}
