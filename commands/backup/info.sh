#!/bin/bash
# commands/backup/info.sh - Backup info command

pgtool_backup_info() {
    local tool="" stanza="" server="" backup_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) pgtool_backup_info_help; return 0 ;;
            --tool) shift; tool="$1"; shift ;;
            --stanza) shift; stanza="$1"; shift ;;
            --server) shift; server="$1"; shift ;;
            --backup-id) shift; backup_id="$1"; shift ;;
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
            if [[ -n "$backup_id" ]]; then
                pgbackrest info --stanza="$stanza" --set="$backup_id" 2>/dev/null
            else
                pgbackrest info --stanza="$stanza" 2>/dev/null
            fi
            ;;
        barman)
            if ! pgtool_backup_barman_check; then pgtool_error "Barman not installed"; return 1; fi
            if [[ -n "$backup_id" && -n "$server" ]]; then
                barman show-backup "$server" "$backup_id" 2>/dev/null
            else
                barman status "$server" 2>/dev/null
            fi
            ;;
        pg_dump)
            if [[ -z "$backup_id" ]]; then
                pgtool_error "pg_dump requires --backup-id <file>"
                return 1
            fi
            if [[ ! -f "$backup_id" ]]; then
                pgtool_error "File not found: $backup_id"
                return 1
            fi
            echo "File: $backup_id"
            echo "Size: $(du -h "$backup_id" 2>/dev/null | cut -f1)"
            echo "Modified: $(stat -f '%Sm' "$backup_id" 2>/dev/null || stat -c '%y' "$backup_id" 2>/dev/null)"
            ;;
        *) pgtool_error "Unknown tool: $tool"; return 1 ;;
    esac
}

pgtool_backup_info_help() {
    cat <<'EOF'
显示备份详细信息

用法: pgtool backup info [选项]

选项:
      --tool TOOL       指定备份工具
      --stanza NAME     pgBackRest stanza
      --server NAME     Barman server
      --backup-id ID    备份ID或文件路径

示例:
  pgtool backup info --stanza=main
  pgtool backup info --backup-id=20240101-120000F
EOF
}
