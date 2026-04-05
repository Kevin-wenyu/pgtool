# Implementation Plan: pgtool monitor command group

## Task Type
- [x] Backend (→ Codex)
- [ ] Frontend (→ Gemini)
- [ ] Fullstack (→ Parallel)

## Overview
Add a new `monitor` command group to pgtool for real-time monitoring of PostgreSQL database, similar to the `top` command. This will provide DBAs with a live view of database activity.

## Technical Solution

### Architecture
1. **New command group**: `commands/monitor/` directory
2. **Terminal UI**: Use ANSI escape sequences for screen clearing and cursor control
3. **Refresh loop**: Bash while loop with configurable interval
4. **Input handling**: Read single keypress (non-blocking) to detect 'q' for quit
5. **Optimized queries**: Use efficient SQL that minimizes database load
6. **Color coding**: Highlight dangerous states (red for slow queries, yellow for waiting)

### Commands
1. `monitor queries` - Real-time active query monitoring (like top)
2. `monitor connections` - Real-time connection count monitoring
3. `monitor replication` - Real-time replication lag monitoring

### Options
- `--interval, -i SECONDS` - Refresh interval (default: 2)
- `--limit, -l N` - Limit display rows (default: 20)
- `--once` - Single execution mode (for scripting)
- All standard global options (--format applies only with --once)

## Implementation Steps

### Step 1: Create command group infrastructure
**File**: `commands/monitor/index.sh`
- Define `PGTOOL_MONITOR_COMMANDS` variable
- Create `pgtool_monitor_help()` function

### Step 2: Add monitor to CLI dispatcher
**File**: `lib/cli.sh:L15`
- Add "monitor" to `PGTOOL_GROUPS` array
- Add "monitor" case to `pgtool_group_desc()`

### Step 3: Create monitor utilities library
**File**: `lib/monitor.sh`
```bash
# Terminal control functions
pgtool_monitor_clear_screen()      # Clear terminal using ANSI sequences
pgtool_monitor_move_cursor_home()  # Move cursor to top-left
pgtool_monitor_hide_cursor()       # Hide cursor during refresh
pgtool_monitor_show_cursor()       # Show cursor on exit

# Input handling
pgtool_monitor_read_key()          # Read single keypress (non-blocking)

# Color coding functions
pgtool_monitor_color_for_state()   # Return ANSI color code based on state
pgtool_monitor_format_row()        # Format row with color

# Refresh loop
pgtool_monitor_refresh_loop()      # Main refresh loop with signal handling
```

### Step 4: Create SQL templates
**Files**: `sql/monitor/*.sql`

`sql/monitor/queries.sql`:
```sql
SELECT pid, usename, datname, client_addr,
       state,
       EXTRACT(EPOCH FROM (now() - query_start))::int as query_time,
       LEFT(query, 80) as query
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY query_start DESC
LIMIT :limit;
```

`sql/monitor/connections.sql`:
```sql
SELECT datname, state, count(*) as count
FROM pg_stat_activity
GROUP BY datname, state
ORDER BY count DESC;
```

`sql/monitor/replication.sql`:
```sql
SELECT client_addr, state,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, flush_lsn)) as lag
FROM pg_stat_replication;
```

### Step 5: Implement monitor queries command
**File**: `commands/monitor/queries.sh`

```bash
pgtool_monitor_queries() {
    # Parse options: --interval, --limit, --once
    # Check if terminal is TTY (for interactive mode)
    # If --once: execute once and exit with specified format
    # Else: enter refresh loop
        # Clear screen
        # Print header (timestamp, interval info)
        # Execute SQL with limit
        # Format output with colors
        # Check for 'q' keypress (non-blocking read with timeout)
        # Sleep for interval
    # On exit: restore cursor, clear screen
}
```

### Step 6: Implement monitor connections command
**File**: `commands/monitor/connections.sh`
- Similar structure to queries.sh
- Show connection count by database and state
- Display totals

### Step 7: Implement monitor replication command
**File**: `commands/monitor/replication.sh`
- Similar structure to queries.sh
- Show replication lag with color coding (red if > 1GB, yellow if > 100MB)

### Step 8: Add signal handling
**File**: `commands/monitor/queries.sh` and others
```bash
# Save terminal state on entry
# Trap SIGINT and SIGTERM to restore cursor
# Trap EXIT to ensure cleanup
```

### Step 9: Test implementation
- Test interactive mode with 'q' to quit
- Test --once mode with different formats
- Test --interval customization
- Test terminal resize handling

## Key Files

| File | Operation | Description |
|------|-----------|-------------|
| `commands/monitor/index.sh` | Create | Command group index |
| `commands/monitor/queries.sh` | Create | Monitor queries command |
| `commands/monitor/connections.sh` | Create | Monitor connections command |
| `commands/monitor/replication.sh` | Create | Monitor replication command |
| `lib/monitor.sh` | Create | Monitor utility functions |
| `lib/cli.sh:L15` | Modify | Add "monitor" to PGTOOL_GROUPS |
| `sql/monitor/queries.sql` | Create | Query monitoring SQL |
| `sql/monitor/connections.sql` | Create | Connection monitoring SQL |
| `sql/monitor/replication.sql` | Create | Replication monitoring SQL |

## Risks and Mitigation

| Risk | Mitigation |
|------|------------|
| Terminal corruption on crash | Proper signal handling with cleanup trap |
| High database load from frequent queries | Use lightweight queries, default 2s interval |
| Non-TTY environments breaking | Check `[[ -t 1 ]]` before entering interactive mode |
| Terminal resize issues | Handle SIGWINCH, recalculate widths |
| Color code incompatibility | Check `$TERM` and `$COLORTERM` |

## Pseudo-code

```bash
# lib/monitor.sh
pgtool_monitor_refresh_loop() {
    local refresh_cmd="$1"
    local interval="$2"

    # Hide cursor
    printf '\033[?25l'

    # Cleanup on exit
    cleanup() {
        printf '\033[?25h'  # Show cursor
        printf '\033[2J\033[H'  # Clear screen, home cursor
    }
    trap cleanup EXIT INT TERM

    while true; do
        # Clear screen
        printf '\033[2J\033[H'

        # Print header
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') | Interval: ${interval}s | Press 'q' to quit ==="
        echo

        # Execute refresh command
        eval "$refresh_cmd"

        # Check for keypress (with timeout)
        if read -rs -t "$interval" -n 1 key; then
            [[ "$key" == "q" ]] && break
        fi
    done
}
```

## SESSION_ID
- CODEX_SESSION: N/A (local planning)
- GEMINI_SESSION: N/A (local planning)
