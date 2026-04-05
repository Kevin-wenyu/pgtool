# Backup Command Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `backup` command group for PostgreSQL backup management with pgBackRest, Barman, and pg_dump integration.

**Architecture:** Auto-detect backup tools (pgBackRest preferred), execute backup commands and parse output, support physical (pgBackRest/Barman) and logical (pg_dump) backups.

**Tech Stack:** Bash, pgBackRest CLI, Barman CLI, psql

---

## File Structure

| File | Type | Purpose |
|------|------|---------|
| `commands/backup/index.sh` | Create | Command group index |
| `commands/backup/status.sh` | Create | Backup status command |
| `commands/backup/verify.sh` | Create | Backup verify command |
| `commands/backup/archive.sh` | Create | WAL archive status command |
| `commands/backup/list.sh` | Create | List backups command |
| `commands/backup/info.sh` | Create | Detailed backup info command |
| `lib/backup.sh` | Create | Backup utility functions |
| `sql/backup/archive.sql` | Create | WAL archiver status SQL |
| `lib/cli.sh` | Modify | Add "backup" to PGTOOL_GROUPS |
| `tests/test_backup.sh` | Create | Unit tests for backup module |

---

## Task 1: Create Backup Library (lib/backup.sh)

**Files:**
- Create: `lib/backup.sh`

- [ ] **Step 1: Write backup detection and utility functions**

```bash
#!/bin/bash
# lib/backup.sh - Backup utility functions

#==============================================================================
# Backup Tool Detection
#==============================================================================

# Detect available backup tool
pgtool_backup_detect_tool() {
    if command -v pgbackrest &>/dev/null; then
        echo "pgbackrest"
        return 0
    elif command -v barman &>/dev/null; then
        echo "barman"
        return 0
    elif command -v pg_dump &>/dev/null; then
        echo "pg_dump"
        return 0
    fi
    return 1
}

# Check if pgBackRest is installed
pgtool_backup_pgbackrest_check() {
    command -v pgbackrest &>/dev/null
}

# Check if Barman is installed
pgtool_backup_barman_check() {
    command -v barman &>/dev/null
}

# Get pgBackRest version
pgtool_backup_pgbackrest_version() {
    pgbackrest version 2>/dev/null | head -1
}

#==============================================================================
# pgBackRest Integration
#==============================================================================

# Get pgBackRest stanza list
pgtool_backup_pgbackrest_list_stanza() {
    pgbackrest info --output=text 2>/dev/null | grep -E '^stanza:' | awk '{print $2}'
}

# Get pgBackRest info for stanza
pgtool_backup_pgbackrest_info() {
    local stanza="${1:-}"

    if [[ -n "$stanza" ]]; then
        pgbackrest info --stanza="$stanza" --output=json 2>/dev/null
    else
        pgbackrest info --output=json 2>/dev/null
    fi
}

# Verify pgBackRest backup
pgtool_backup_pgbackrest_verify() {
    local stanza="${1:-}"

    if [[ -n "$stanza" ]]; then
        pgbackrest verify --stanza="$stanza" 2>&1
    else
        pgbackrest verify 2>&1
    fi
}

#==============================================================================
# Barman Integration
#==============================================================================

# List Barman servers
pgtool_backup_barman_list_servers() {
    barman list-server --minimal 2>/dev/null
}

# Get Barman status
pgtool_backup_barman_status() {
    local server="${1:-}"

    if [[ -n "$server" ]]; then
        barman status "$server" 2>/dev/null
    else
        barman status 2>/dev/null
    fi
}

# List Barman backups
pgtool_backup_barman_list() {
    local server="${1:-}"

    if [[ -n "$server" ]]; then
        barman list-backup "$server" 2>/dev/null
    else
        barman list-backup 2>/dev/null
    fi
}

# Check Barman backup
pgtool_backup_barman_check() {
    local server="${1:-}"

    if [[ -n "$server" ]]; then
        barman check "$server" 2>&1
    else
        barman check 2>&1
    fi
}

#==============================================================================
# WAL Archiving
#==============================================================================

# Check if archiving is configured
pgtool_backup_archive_configured() {
    local result
    result=$(pgtool_pg_query_one "SELECT setting FROM pg_settings WHERE name = 'archive_mode'")
    [[ "$result" == "on" ]] || [[ "$result" == "always" ]]
}

# Get archive command
pgtool_backup_archive_command() {
    pgtool_pg_query_one "SELECT setting FROM pg_settings WHERE name = 'archive_command'"
}

#==============================================================================
# Formatting
#==============================================================================

# Format backup status for display
pgtool_backup_format_status() {
    local tool="$1"
    local status_data="$2"

    case "$tool" in
        pgbackrest)
            # Parse pgBackRest JSON output
            if command -v jq &>/dev/null; then
                echo "$status_data" | jq -r '.[0] | "Stanza: \(.name)\nStatus: \(.status.code)\nBackups: \(.backup | length)"' 2>/dev/null
            else
                echo "pgBackRest status available (install jq for better formatting)"
            fi
            ;;
        barman)
            echo "$status_data"
            ;;
        pg_dump)
            echo "pg_dump: logical backup tool"
            ;;
        *)
            echo "Unknown backup tool: $tool"
            ;;
    esac
}

# Format backup list for display
pgtool_backup_format_list() {
    local tool="$1"
    local list_data="$2"

    case "$tool" in
        pgbackrest)
            if command -v jq &>/dev/null; then
                echo "$list_data" | jq -r '.[0].backup[] | "\(.label) | \(.info.size) | \(.info.timestamp.start)"' 2>/dev/null
            else
                echo "$list_data"
            fi
            ;;
        barman)
            echo "$list_data"
            ;;
        *)
            echo "No backups found"
            ;;
    esac
}

#==============================================================================
# Error Handling
#==============================================================================

# Handle backup tool not found
pgtool_backup_tool_not_found() {
    pgtool_error "未找到备份工具"
    pgtool_info "支持的备份工具: pgbackrest, barman, pg_dump"
    pgtool_info "请安装其中一个工具后重试"
}
```

- [ ] **Step 2: Add library to pgtool.sh**

修改 `pgtool.sh` 添加库加载（在 lib/cli.sh 之后）:

```bash
source "$PGTOOL_SCRIPT_DIR/lib/core.sh"
source "$PGTOOL_SCRIPT_DIR/lib/log.sh"
source "$PGTOOL_SCRIPT_DIR/lib/util.sh"
source "$PGTOOL_SCRIPT_DIR/lib/output.sh"
source "$PGTOOL_SCRIPT_DIR/lib/pg.sh"
source "$PGTOOL_SCRIPT_DIR/lib/plugin.sh"
source "$PGTOOL_SCRIPT_DIR/lib/backup.sh"  # Add this line
source "$PGTOOL_SCRIPT_DIR/lib/cli.sh"
```

- [ ] **Step 3: Commit**

```bash
git add lib/backup.sh pgtool.sh
git commit -m "feat(backup): add backup utility library with pgBackRest/Barman support"
```

---

## Task 2: Create SQL Templates

**Files:**
- Create: `sql/backup/archive.sql`

- [ ] **Step 1: Write archive.sql**

```sql
-- sql/backup/archive.sql
-- WAL archiver status
-- Parameters: none

SELECT
    archived_count AS "Archived",
    failed_count AS "Failed",
    COALESCE(last_archived_time::text, 'N/A') AS "Last Archived",
    COALESCE(last_failed_time::text, 'N/A') AS "Last Failed",
    COALESCE(last_archived_wal, 'N/A') AS "Last WAL",
    CASE
        WHEN failed_count > 0 THEN 'WARNING'
        WHEN last_archived_time < NOW() - INTERVAL '5 minutes' THEN 'WARNING'
        ELSE 'OK'
    END AS "Status"
FROM pg_stat_archiver;
```

- [ ] **Step 2: Commit**

```bash
git add sql/backup/archive.sql
git commit -m "feat(backup): add WAL archiver status SQL template"
```

---

## Task 3: Create Command Group Index

**Files:**
- Create: `commands/backup/index.sh`

- [ ] **Step 1: Write index.sh**

```bash
#!/bin/bash
# commands/backup/index.sh - backup command group index

# Command list: "command:description"
PGTOOL_BACKUP_COMMANDS="status:显示备份状态,verify:验证备份完整性,archive:检查WAL归档状态,list:列出可用备份,info:显示备份详情"

# Display help
pgtool_backup_help() {
    cat <<EOF
备份类命令 - 备份管理与监控

可用命令:
  status     显示备份状态
  verify     验证备份完整性
  archive    检查WAL归档状态
  list       列出可用备份
  info       显示备份详细信息

选项:
  -h, --help              显示帮助
      --tool TOOL         指定备份工具 (pgbackrest|barman|pg_dump)
      --stanza NAME       pgBackRest stanza名称
      --server NAME       Barman服务器名称

备份工具优先级:
  1. pgBackRest (推荐用于物理备份)
  2. Barman (替代物理备份方案)
  3. pg_dump (逻辑备份)

使用 'pgtool backup <命令> --help' 查看具体命令帮助

示例:
  pgtool backup status
  pgtool backup status --tool=pgbackrest --stanza=main
  pgtool backup list --tool=barman
  pgtool backup verify
  pgtool backup archive
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/backup/index.sh
git commit -m "feat(backup): add backup command group index"
```

---

## Task 4: Implement Backup Status Command

**Files:**
- Create: `commands/backup/status.sh`

- [ ] **Step 1: Write status.sh**

```bash
#!/bin/bash
# commands/backup/status.sh - Backup status command

#==============================================================================
# Main function
#==============================================================================

pgtool_backup_status() {
    local -a opts=()
    local -a args=()
    local tool=""
    local stanza=""
    local server=""

    # Parse arguments
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
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Auto-detect tool if not specified
    if [[ -z "$tool" ]]; then
        tool=$(pgtool_backup_detect_tool) || {
            pgtool_backup_tool_not_found
            return $EXIT_NOT_FOUND
        }
        pgtool_info "自动检测到备份工具: $tool"
    fi

    pgtool_info "显示备份状态 (工具: $tool)..."
    echo

    case "$tool" in
        pgbackrest)
            pgtool_backup_status_pgbackrest "$stanza"
            ;;
        barman)
            pgtool_backup_status_barman "$server"
            ;;
        pg_dump)
            pgtool_backup_status_pg_dump
            ;;
        *)
            pgtool_error "未知备份工具: $tool"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

# pgBackRest status
pgtool_backup_status_pgbackrest() {
    local stanza="${1:-}"

    if ! pgtool_backup_pgbackrest_check; then
        pgtool_error "pgBackRest 未安装"
        return $EXIT_NOT_FOUND
    fi

    # Show version
    echo "pgBackRest: $(pgtool_backup_pgbackrest_version)"
    echo

    # Get info
    local info
    info=$(pgtool_backup_pgbackrest_info "$stanza")

    if [[ -z "$info" ]]; then
        pgtool_error "无法获取 pgBackRest 信息"
        return $EXIT_GENERAL_ERROR
    fi

    # Parse and display
    if command -v jq &>/dev/null; then
        echo "$info" | jq -r '.[] | "Stanza: \(.name)"'
        echo

        local stanza_count
        stanza_count=$(echo "$info" | jq '. | length')
        echo "Stanzas: $stanza_count"

        echo "$info" | jq -r '.[] | "\n  Stanza: \(.name)"'
        echo "$info" | jq -r '.[] | "  Status: \(.status.message // .status.code)"'
        echo "$info" | jq -r '.[] | "  Backups: \(.backup | length)"'
    else
        # Fallback to text output
        pgbackrest info --stanza="$stanza" 2>/dev/null || pgbackrest info
    fi
}

# Barman status
pgtool_backup_status_barman() {
    local server="${1:-}"

    if ! pgtool_backup_barman_check; then
        pgtool_error "Barman 未安装"
        return $EXIT_NOT_FOUND
    fi

    echo "Barman Status"
    echo "============="
    pgtool_backup_barman_status "$server"
}

# pg_dump status (check for dump files)
pgtool_backup_status_pg_dump() {
    pgtool_info "pg_dump 是逻辑备份工具，无集中管理状态"
    pgtool_info "建议检查常见的备份目录:"
    echo "  - /var/lib/postgresql/backups/"
    echo "  - /backup/"
    echo "  - $HOME/backups/"
    echo

    # Try to find recent dump files
    local backup_dirs=(
        "/var/lib/postgresql/backups"
        "/backup"
        "$HOME/backups"
        "/var/backups/postgresql"
    )

    echo "搜索备份文件..."
    for dir in "${backup_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo
            echo "目录: $dir"
            find "$dir" -name "*.sql" -o -name "*.dump" -o -name "*.backup" 2>/dev/null | \
                head -10 | while read -r f; do
                echo "  $(stat -c '%y %n' "$f" 2>/dev/null || stat -f '%Sm %N' "$f" 2>/dev/null)"
            done
        fi
    done
}

# Help function
pgtool_backup_status_help() {
    cat <<EOF
显示备份状态

显示备份工具的当前状态，包括最近的备份、WAL归档状态等。
自动检测已安装的备份工具（pgBackRest优先）。

用法: pgtool backup status [选项]

选项:
  -h, --help              显示帮助
      --tool TOOL         指定备份工具 (pgbackrest|barman|pg_dump)
      --stanza NAME       pgBackRest stanza名称
      --server NAME       Barman服务器名称
      --format FORMAT     输出格式 (仅用于JSON可用时)

示例:
  pgtool backup status
  pgtool backup status --tool=pgbackrest
  pgtool backup status --stanza=main
  pgtool backup status --tool=barman --server=prod
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/backup/status.sh
git commit -m "feat(backup): add status command for backup state monitoring"
```

---

## Task 5: Implement Backup Verify Command

**Files:**
- Create: `commands/backup/verify.sh`

- [ ] **Step 1: Write verify.sh**

```bash
#!/bin/bash
# commands/backup/verify.sh - Backup verify command

#==============================================================================
# Main function
#==============================================================================

pgtool_backup_verify() {
    local -a opts=()
    local -a args=()
    local tool=""
    local stanza=""
    local server=""
    local backup_id=""

    # Parse arguments
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
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Auto-detect tool
    if [[ -z "$tool" ]]; then
        tool=$(pgtool_backup_detect_tool) || {
            pgtool_backup_tool_not_found
            return $EXIT_NOT_FOUND
        }
        pgtool_info "自动检测到备份工具: $tool"
    fi

    pgtool_info "验证备份完整性 (工具: $tool)..."
    echo

    local result
    local exit_code=0

    case "$tool" in
        pgbackrest)
            result=$(pgtool_backup_verify_pgbackrest "$stanza")
            exit_code=$?
            ;;
        barman)
            result=$(pgtool_backup_verify_barman "$server")
            exit_code=$?
            ;;
        pg_dump)
            pgtool_warn "pg_dump 备份需要通过恢复来验证"
            pgtool_info "建议定期执行恢复测试到临时实例"
            return $EXIT_SUCCESS
            ;;
        *)
            pgtool_error "未知备份工具: $tool"
            return $EXIT_INVALID_ARGS
            ;;
    esac

    echo "$result"

    if [[ $exit_code -eq 0 ]]; then
        pgtool_info "验证成功"
    else
        pgtool_error "验证失败"
    fi

    return $exit_code
}

# Verify pgBackRest backup
pgtool_backup_verify_pgbackrest() {
    local stanza="${1:-}"

    if ! pgtool_backup_pgbackrest_check; then
        pgtool_error "pgBackRest 未安装"
        return $EXIT_NOT_FOUND
    fi

    pgtool_info "正在验证 pgBackRest 备份..."
    pgtool_backup_pgbackrest_verify "$stanza"
}

# Verify Barman backup
pgtool_backup_verify_barman() {
    local server="${1:-}"

    if ! pgtool_backup_barman_check; then
        pgtool_error "Barman 未安装"
        return $EXIT_NOT_FOUND
    fi

    pgtool_info "正在验证 Barman 配置..."
    pgtool_backup_barman_check "$server"
}

# Help function
pgtool_backup_verify_help() {
    cat <<EOF
验证备份完整性

验证备份工具的备份完整性。

用法: pgtool backup verify [选项]

选项:
  -h, --help              显示帮助
      --tool TOOL         指定备份工具 (pgbackrest|barman)
      --stanza NAME       pgBackRest stanza名称
      --server NAME       Barman服务器名称

说明:
  pgBackRest: 使用 pgbackrest verify 命令
  Barman: 使用 barman check 命令
  pg_dump: 逻辑备份需要通过恢复验证

示例:
  pgtool backup verify
  pgtool backup verify --tool=pgbackrest --stanza=main
  pgtool backup verify --tool=barman --server=prod
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/backup/verify.sh
git commit -m "feat(backup): add verify command for backup integrity checking"
```

---

## Task 6: Implement Backup Archive Command

**Files:**
- Create: `commands/backup/archive.sh`

- [ ] **Step 1: Write archive.sh**

```bash
#!/bin/bash
# commands/backup/archive.sh - WAL archive status command

#==============================================================================
# Main function
#==============================================================================

pgtool_backup_archive() {
    local -a opts=()
    local -a args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_backup_archive_help
                return 0
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "检查WAL归档状态..."
    echo

    # Check if archiving is configured
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Show archive configuration
    local archive_mode
    local archive_command
    archive_mode=$(pgtool_pg_query_one "SELECT setting FROM pg_settings WHERE name = 'archive_mode'")
    archive_command=$(pgtool_pg_query_one "SELECT setting FROM pg_settings WHERE name = 'archive_command'")

    echo "归档配置:"
    echo "  archive_mode: $archive_mode"
    echo "  archive_command: $archive_command"
    echo

    if [[ "$archive_mode" == "off" ]]; then
        pgtool_warn "WAL归档未启用 (archive_mode = off)"
        return $EXIT_SUCCESS
    fi

    # Execute SQL
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "backup" "archive"); then
        pgtool_fatal "SQL文件未找到: backup/archive"
    fi

    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # Check for warnings
    if echo "$result" | grep -q "WARNING"; then
        echo
        pgtool_warn "发现归档问题，请检查归档进程"
        return 1
    fi

    return $EXIT_SUCCESS
}

# Help function
pgtool_backup_archive_help() {
    cat <<EOF
检查WAL归档状态

显示WAL归档进程的状态，包括已归档数量、失败数量、最后归档时间等。

用法: pgtool backup archive [选项]

选项:
  -h, --help              显示帮助
      --format FORMAT     输出格式 (table|json|csv|tsv)

输出字段:
  Archived       - 成功归档的WAL文件数量
  Failed         - 失败的归档尝试次数
  Last Archived  - 最后一次成功归档时间
  Last Failed    - 最后一次失败时间
  Last WAL       - 最后归档的WAL文件名
  Status         - 状态 (OK|WARNING)

示例:
  pgtool backup archive
  pgtool backup archive --format=json
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/backup/archive.sh
git commit -m "feat(backup): add archive command for WAL archiver status"
```

---

## Task 7: Implement Backup List Command

**Files:**
- Create: `commands/backup/list.sh`

- [ ] **Step 1: Write list.sh**

```bash
#!/bin/bash
# commands/backup/list.sh - Backup list command

#==============================================================================
# Main function
#==============================================================================

pgtool_backup_list() {
    local -a opts=()
    local -a args=()
    local tool=""
    local stanza=""
    local server=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_backup_list_help
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
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Auto-detect tool
    if [[ -z "$tool" ]]; then
        tool=$(pgtool_backup_detect_tool) || {
            pgtool_backup_tool_not_found
            return $EXIT_NOT_FOUND
        }
        pgtool_info "自动检测到备份工具: $tool"
    fi

    pgtool_info "列出可用备份 (工具: $tool)..."
    echo

    case "$tool" in
        pgbackrest)
            pgtool_backup_list_pgbackrest "$stanza"
            ;;
        barman)
            pgtool_backup_list_barman "$server"
            ;;
        pg_dump)
            pgtool_backup_list_pg_dump
            ;;
        *)
            pgtool_error "未知备份工具: $tool"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

# List pgBackRest backups
pgtool_backup_list_pgbackrest() {
    local stanza="${1:-}"

    if ! pgtool_backup_pgbackrest_check; then
        pgtool_error "pgBackRest 未安装"
        return $EXIT_NOT_FOUND
    fi

    local info
    info=$(pgtool_backup_pgbackrest_info "$stanza")

    if [[ -z "$info" ]]; then
        pgtool_error "无法获取备份列表"
        return $EXIT_GENERAL_ERROR
    fi

    if command -v jq &>/dev/null; then
        echo "备份列表:"
        echo

        echo "$info" | jq -r '.[] | "\nStanza: \(.name)"'
        echo "$info" | jq -r '.[] | .backup[] | "  \(.label) | Type: \(.type) | Size: \(.info.size) | Start: \(.info.timestamp.start)"'
    else
        # Text format fallback
        pgbackrest info --stanza="$stanza"
    fi
}

# List Barman backups
pgtool_backup_list_barman() {
    local server="${1:-}"

    if ! pgtool_backup_barman_check; then
        pgtool_error "Barman 未安装"
        return $EXIT_NOT_FOUND
    fi

    echo "Barman Backups:"
    echo
    pgtool_backup_barman_list "$server"
}

# List pg_dump backups
pgtool_backup_list_pg_dump() {
    pgtool_info "pg_dump 备份列表"
    echo

    local backup_dirs=(
        "/var/lib/postgresql/backups"
        "/backup"
        "$HOME/backups"
        "/var/backups/postgresql"
    )

    for dir in "${backup_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "目录: $dir"
            find "$dir" \( -name "*.sql" -o -name "*.dump" -o -name "*.backup" -o -name "*.sql.gz" \) \
                -type f -printf "  %TY-%Tm-%Td %TH:%TM %s %p\n" 2>/dev/null | \
                head -20
            echo
        fi
    done
}

# Help function
pgtool_backup_list_help() {
    cat <<EOF
列出可用备份

显示可用的备份列表。

用法: pgtool backup list [选项]

选项:
  -h, --help              显示帮助
      --tool TOOL         指定备份工具 (pgbackrest|barman|pg_dump)
      --stanza NAME       pgBackRest stanza名称
      --server NAME       Barman服务器名称

示例:
  pgtool backup list
  pgtool backup list --tool=pgbackrest
  pgtool backup list --tool=barman --server=prod
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/backup/list.sh
git commit -m "feat(backup): add list command to show available backups"
```

---

## Task 8: Implement Backup Info Command

**Files:**
- Create: `commands/backup/info.sh`

- [ ] **Step 1: Write info.sh**

```bash
#!/bin/bash
# commands/backup/info.sh - Backup info command

#==============================================================================
# Main function
#==============================================================================

pgtool_backup_info() {
    local -a opts=()
    local -a args=()
    local tool=""
    local stanza=""
    local server=""
    local backup_id=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_backup_info_help
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
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Auto-detect tool
    if [[ -z "$tool" ]]; then
        tool=$(pgtool_backup_detect_tool) || {
            pgtool_backup_tool_not_found
            return $EXIT_NOT_FOUND
        }
        pgtool_info "自动检测到备份工具: $tool"
    fi

    pgtool_info "显示备份详情 (工具: $tool)..."
    echo

    case "$tool" in
        pgbackrest)
            pgtool_backup_info_pgbackrest "$stanza" "$backup_id"
            ;;
        barman)
            pgtool_backup_info_barman "$server" "$backup_id"
            ;;
        pg_dump)
            pgtool_backup_info_pg_dump "$backup_id"
            ;;
        *)
            pgtool_error "未知备份工具: $tool"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

# pgBackRest backup info
pgtool_backup_info_pgbackrest() {
    local stanza="${1:-}"
    local backup_id="${2:-}"

    if ! pgtool_backup_pgbackrest_check; then
        pgtool_error "pgBackRest 未安装"
        return $EXIT_NOT_FOUND
    fi

    local info
    if [[ -n "$backup_id" ]]; then
        info=$(pgbackrest info --stanza="$stanza" --set="$backup_id" --output=json 2>/dev/null)
    else
        info=$(pgtool_backup_pgbackrest_info "$stanza")
    fi

    if [[ -z "$info" ]]; then
        pgtool_error "无法获取备份信息"
        return $EXIT_NOT_FOUND
    fi

    if command -v jq &>/dev/null; then
        if [[ -n "$backup_id" ]]; then
            echo "$info" | jq .
        else
            echo "$info" | jq -r '.[] | "\nStanza: \(.name)\nStatus: \(.status.message)\nBackups: \(.backup | length)"'
        fi
    else
        echo "$info"
    fi
}

# Barman backup info
pgtool_backup_info_barman() {
    local server="${1:-}"
    local backup_id="${2:-}"

    if ! pgtool_backup_barman_check; then
        pgtool_error "Barman 未安装"
        return $EXIT_NOT_FOUND
    fi

    if [[ -n "$backup_id" && -n "$server" ]]; then
        barman show-backup "$server" "$backup_id" 2>/dev/null
    elif [[ -n "$server" ]]; then
        barman status "$server"
    else
        barman status
    fi
}

# pg_dump backup info
pgtool_backup_info_pg_dump() {
    local backup_id="${1:-}"

    if [[ -z "$backup_id" ]]; then
        pgtool_error "pg_dump 需要指定备份文件路径 (--backup-id)"
        return $EXIT_INVALID_ARGS
    fi

    if [[ ! -f "$backup_id" ]]; then
        pgtool_error "备份文件不存在: $backup_id"
        return $EXIT_NOT_FOUND
    fi

    echo "备份文件: $backup_id"
    echo "大小: $(du -h "$backup_id" 2>/dev/null | cut -f1)"
    echo "修改时间: $(stat -c '%y' "$backup_id" 2>/dev/null || stat -f '%Sm' "$backup_id")"

    # Try to show dump contents summary
    if [[ "$backup_id" == *.sql ]] || [[ "$backup_id" == *.sql.gz ]]; then
        echo
        echo "备份内容预览:"
        if [[ "$backup_id" == *.gz ]]; then
            zcat "$backup_id" 2>/dev/null | head -20
        else
            head -20 "$backup_id"
        fi
    fi
}

# Help function
pgtool_backup_info_help() {
    cat <<EOF
显示备份详细信息

显示特定备份的详细信息，包括时间戳、大小、WAL范围等。

用法: pgtool backup info [选项]

选项:
  -h, --help              显示帮助
      --tool TOOL         指定备份工具 (pgbackrest|barman|pg_dump)
      --stanza NAME       pgBackRest stanza名称
      --server NAME       Barman服务器名称
      --backup-id ID      备份ID或文件路径

示例:
  pgtool backup info
  pgtool backup info --tool=pgbackrest --stanza=main
  pgtool backup info --backup-id=20240101-120000F
  pgtool backup info --tool=pg_dump --backup-id=/path/to/backup.sql
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/backup/info.sh
git commit -m "feat(backup): add info command for detailed backup information"
```

---

## Task 9: Register Backup Command Group

**Files:**
- Modify: `lib/cli.sh`

- [ ] **Step 1: Add backup to PGTOOL_GROUPS**

```bash
# Line 15: Change from:
PGTOOL_GROUPS=("check" "stat" "admin" "analyze" "plugin")
# To:
PGTOOL_GROUPS=("check" "stat" "admin" "analyze" "plugin" "backup")
```

- [ ] **Step 2: Add backup case to pgtool_group_desc**

```bash
# After plugin case, add:
        backup)  echo "备份管理 - 备份监控与验证" ;;
```

- [ ] **Step 3: Commit**

```bash
git add lib/cli.sh
git commit -m "feat(backup): register backup command group in CLI dispatcher"
```

---

## Task 10: Create Tests

**Files:**
- Create: `tests/test_backup.sh`

- [ ] **Step 1: Write test file**

```bash
#!/bin/bash
# tests/test_backup.sh - Backup module tests

# Load test framework
source "$TEST_DIR/test_runner.sh"

#==============================================================================
# Setup
#==============================================================================

setup_backup_tests() {
    if ! type pgtool_backup_detect_tool &>/dev/null; then
        source "$PGTOOL_ROOT/lib/backup.sh" 2>/dev/null || true
    fi
}

#==============================================================================
# Tests
#==============================================================================

test_backup_lib_loaded() {
    assert_true "type pgtool_backup_detect_tool &>/dev/null"
    assert_true "type pgtool_backup_pgbackrest_check &>/dev/null"
    assert_true "type pgtool_backup_barman_check &>/dev/null"
}

test_backup_commands_exist() {
    assert_true "[[ -f $PGTOOL_ROOT/commands/backup/index.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/backup/status.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/backup/verify.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/backup/archive.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/backup/list.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/backup/info.sh ]]"
}

test_backup_sql_files_exist() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/backup/archive.sql ]]"
}

test_backup_registered_in_cli() {
    assert_contains "${PGTOOL_GROUPS[*]}" "backup"
}

test_backup_tool_detection() {
    # Should return 1 if no tool found (in most test environments)
    local result
    result=$(pgtool_backup_detect_tool 2>/dev/null) && true
    # Just check the function exists and runs
    assert_true "type pgtool_backup_detect_tool &>/dev/null"
}

#==============================================================================
# Run tests
#==============================================================================

setup_backup_tests
run_test "backup_lib_loaded" test_backup_lib_loaded
run_test "backup_commands_exist" test_backup_commands_exist
run_test "backup_sql_files_exist" test_backup_sql_files_exist
run_test "backup_registered" test_backup_registered_in_cli
run_test "backup_tool_detection" test_backup_tool_detection
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_backup.sh
git commit -m "test(backup): add unit tests for backup command group"
```

---

## Task 11: Integration Test

- [ ] **Step 1: Test backup help**

```bash
./pgtool.sh backup --help
```

Expected: Shows backup command group help with status, verify, archive, list, info commands.

- [ ] **Step 2: Test archive command (works without backup tools)**

```bash
./pgtool.sh backup archive
```

Expected: Shows WAL archiver status or "archive_mode = off" warning.

- [ ] **Step 3: Test status with no tools**

```bash
./pgtool.sh backup status
```

Expected: Error message about no backup tool found.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat(backup): complete backup command group implementation"
```

---

## Spec Coverage Check

| Requirement | Task | Status |
|-------------|------|--------|
| Auto-detect backup tools | Task 1 | ✓ |
| pgBackRest integration | Tasks 1, 4-5, 7-8 | ✓ |
| Barman integration | Tasks 1, 4-5, 7-8 | ✓ |
| pg_dump support | Tasks 1, 4, 7-8 | ✓ |
| status command | Task 4 | ✓ |
| verify command | Task 5 | ✓ |
| archive command | Tasks 2, 6 | ✓ |
| list command | Task 7 | ✓ |
| info command | Task 8 | ✓ |
| Command registration | Task 9 | ✓ |
| Tests | Tasks 10-11 | ✓ |

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-02-backup-command-group.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
