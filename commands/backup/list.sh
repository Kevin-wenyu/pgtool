#!/bin/bash
# commands/backup/list.sh - Backup list command

pgtool_backup_list() {
    local tool="" stanza="" server=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) pgtool_backup_list_help; return 0 ;;
            --tool) shift; tool="$1"; shift ;;
            --stanza) shift; stanza="$1"; shift ;;
            --server) shift; server="$1"; shift ;;
            --format) shift; PGTOOL_FORMAT="$1"; shift ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname) shift; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$tool" ]]; then
        tool=$(pgtool_backup_detect_tool 2>/dev/null) || { pgtool_backup_tool_not_found; return 1; }
    fi

    case "$tool" in
        pgbackrest)
            if ! pgtool_backup_pgbackrest_check; then pgtool_error "pgBackRest not installed"; return 1; fi
            local info=$(pgtool_backup_pgbackrest_info "$stanza")
            if command -v jq &>/dev/null; then
                echo "$info" | jq -r '.[].backup[] | "\(.label) | \(.type) | \(.info.size)"' 2>/dev/null
            else
                pgbackrest info --stanza="$stanza" 2>/dev/null
            fi
            ;;
        barman)
            if ! pgtool_backup_barman_check; then pgtool_error "Barman not installed"; return 1; fi
            pgtool_backup_barman_list "$server"
            ;;
        pg_dump)
            echo "pg_dump logical backups:"
            for dir in "$HOME/backups" "/backup" "/var/lib/postgresql/backups"; do
                [[ -d "$dir" ]] && find "$dir" -name "*.sql*" -o -name "*.dump*" 2>/dev/null | head -5
            done
            ;;
        *) pgtool_error "Unknown tool: $tool"; return 1 ;;
    esac
}

pgtool_backup_list_help() {
    cat <<'EOF'
列出可用备份

用法: pgtool backup list [选项]

选项:
      --tool TOOL      指定备份工具 (pgbackrest|barman|pg_dump)
      --stanza NAME    pgBackRest stanza名称
      --server NAME    Barman服务器名称

示例:
  pgtool backup list
  pgtool backup list --tool=pgbackrest --stanza=main
EOF
}
