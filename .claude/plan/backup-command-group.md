# Implementation Plan: pgtool backup command group

## Task Type
- [x] Backend (→ Codex)
- [ ] Frontend (→ Gemini)
- [ ] Fullstack (→ Parallel)

## Overview
Add a new `backup` command group to pgtool for database backup management and monitoring. This provides DBAs with tools to check backup status, verify backup integrity, and monitor backup history.

## Technical Solution

### Architecture
1. **New command group**: `commands/backup/` directory
2. **Integration with pgBackRest**: Primary backup tool support
3. **Integration with pg_dump**: Logical backup support
4. **Integration with WAL archiving**: Archive status monitoring
5. **Status tracking**: Parse backup tool output and present in unified format

### Commands
1. `backup status` - Show backup status and history
2. `backup verify` - Verify backup integrity
3. `backup archive` - Check WAL archiving status
4. `backup list` - List available backups
5. `backup info` - Show detailed backup information

### Options
- `--tool TOOL` - Specify backup tool (pgbackrest, pg_dump, barman)
- `--stanza NAME` - pgBackRest stanza name
- `--format` - Output format (table, json)
- All standard global options

## Implementation Steps

### Step 1: Create command group infrastructure
**File**: `commands/backup/index.sh`
```bash
PGTOOL_BACKUP_COMMANDS="status:显示备份状态,verify:验证备份完整性,archive:检查WAL归档状态,list:列出可用备份,info:显示备份详情"

pgtool_backup_help() {
    # Help text for backup commands
}
```

### Step 2: Add backup to CLI dispatcher
**File**: `lib/cli.sh:L15`
- Add "backup" to `PGTOOL_GROUPS` array
- Add "backup" case to `pgtool_group_desc()`

### Step 3: Create backup utilities library
**File**: `lib/backup.sh`
```bash
# Detection functions
pgtool_backup_detect_tool()          # Auto-detect backup tool (pgbackrest, barman)
pgtool_backup_pgbackrest_check()     # Check if pgbackrest is installed
pgtool_backup_barman_check()         # Check if barman is installed

# pgBackRest integration
pgtool_backup_pgbackrest_info()      # Get pgbackrest info --output=json
pgtool_backup_pgbackrest_verify()    # Run pgbackrest verify

# Barman integration
pgtool_backup_barman_list()          # Get barman list-backup
pgtool_backup_barman_status()        # Get barman status

# WAL archiving
pgtool_backup_archive_status()       # Check pg_stat_archiver
pgtool_backup_archive_lag()          # Calculate archive lag

# Output formatting
pgtool_backup_format_status()        # Format status output
pgtool_backup_format_list()          # Format backup list
```

### Step 4: Implement backup status command
**File**: `commands/backup/status.sh`

```bash
pgtool_backup_status() {
    # Parse options: --tool, --stanza
    # Auto-detect backup tool if not specified
    # Check which tool is available (pgbackrest, barman, pg_dump cron)

    # If pgbackrest:
        # Run: pgbackrest info --stanza=<stanza> --output=json
        # Parse JSON output
        # Display: last backup time, size, WAL archive status

    # If barman:
        # Run: barman status <server>
        # Parse output
        # Display: current status, last backup, WAL archive status

    # If pg_dump:
        # Check for recent backup files in common locations
        # Display: found backups with timestamps
}
```

### Step 5: Implement backup verify command
**File**: `commands/backup/verify.sh`
```bash
pgtool_backup_verify() {
    # Parse options: --tool, --stanza, --backup-id
    # Run verification based on tool:
        # pgbackrest: pgbackrest verify --stanza=<stanza>
        # barman: barman check <server>
    # Display verification results
}
```

### Step 6: Implement backup archive command
**File**: `commands/backup/archive.sh`
```bash
pgtool_backup_archive() {
    # Query pg_stat_archiver for archiving stats
    # Calculate lag between current WAL and archived WAL
    # Display: archived_count, failed_count, last_archived_time, lag
}
```

**File**: `sql/backup/archive.sql`
```sql
SELECT
    archived_count,
    failed_count,
    last_archived_time,
    last_failed_time,
    EXTRACT(EPOCH FROM (now() - last_archived_time))/60 as lag_minutes,
    CASE
        WHEN failed_count > 0 THEN 'ERROR'
        WHEN EXTRACT(EPOCH FROM (now() - last_archived_time)) > 600 THEN 'WARNING'
        ELSE 'OK'
    END as status
FROM pg_stat_archiver;
```

### Step 7: Implement backup list command
**File**: `commands/backup/list.sh`
```bash
pgtool_backup_list() {
    # Parse options: --tool, --stanza
    # List backups based on tool:
        # pgbackrest: Parse pgbackrest info --output=json
        # barman: barman list-backup <server>
    # Display: backup ID, timestamp, size, type (full/incr)
}
```

### Step 8: Implement backup info command
**File**: `commands/backup/info.sh`
```bash
pgtool_backup_info() {
    # Parse options: --tool, --stanza, --backup-id
    # Show detailed info for specific backup
    # Display: timestamp, size, WAL range, tablespaces, etc.
}
```

### Step 9: Create SQL templates for backup monitoring
**Files**: `sql/backup/*.sql`

`sql/backup/archive.sql` - WAL archiver status
`sql/backup/oldest-backup.sql` - Find oldest backup in system

### Step 10: Test implementation
- Test with pgBackRest installed
- Test with Barman installed
- Test without any backup tool (graceful degradation)
- Test JSON output format
- Test error handling for missing stanzas

## Key Files

| File | Operation | Description |
|------|-----------|-------------|
| `commands/backup/index.sh` | Create | Command group index |
| `commands/backup/status.sh` | Create | Backup status command |
| `commands/backup/verify.sh` | Create | Backup verify command |
| `commands/backup/archive.sh` | Create | WAL archive command |
| `commands/backup/list.sh` | Create | Backup list command |
| `commands/backup/info.sh` | Create | Backup info command |
| `lib/backup.sh` | Create | Backup utility functions |
| `lib/cli.sh:L15` | Modify | Add "backup" to PGTOOL_GROUPS |
| `sql/backup/archive.sql` | Create | WAL archive status SQL |

## Risks and Mitigation

| Risk | Mitigation |
|------|------------|
| Backup tool not installed | Auto-detect and graceful error message |
| pgBackRest JSON format changes | Version detection and fallback to text parsing |
| Permission issues accessing backups | Check permissions before running commands |
| Slow pgbackrest info command | Add --timeout option and warn user |
| Multiple backup tools installed | Default to pgbackrest, allow --tool override |

## Dependencies

The backup commands will attempt to use the following tools if available:
- pgBackRest (preferred for physical backups)
- Barman (alternative for physical backups)
- pg_dump (for logical backups)

## Pseudo-code

```bash
# lib/backup.sh
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

pgtool_backup_pgbackrest_info() {
    local stanza="${1:-}"

    if [[ -z "$stanza" ]]; then
        # Try to auto-detect stanza
        stanza=$(pgbackrest info --output=text 2>/dev/null | head -1)
    fi

    pgbackrest info --stanza="$stanza" --output=json 2>/dev/null
}
```

## SESSION_ID
- CODEX_SESSION: N/A (local planning)
- GEMINI_SESSION: N/A (local planning)
