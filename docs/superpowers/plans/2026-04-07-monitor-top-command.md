# Monitor Top Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool monitor top` interactive command that shows a top-like real-time view of PostgreSQL activity.

**Architecture:** Uses a bash loop with clear/refresh pattern. Queries pg_stat_activity every N seconds. Handles terminal resize, keyboard input for quit/refresh/pause.

**Tech Stack:** Bash, PostgreSQL SQL, psql, terminal control

---

## File Structure

- **Create:** `sql/monitor/top.sql` - SQL for activity snapshot
- **Create:** `commands/monitor/top.sh` - Interactive TUI implementation
- **Modify:** `commands/monitor/index.sh` - Register command
- **Create:** `tests/test_monitor_top.sh` - Unit tests

---

### Task 1: Create SQL Query

**Files:**
- Create: `sql/monitor/top.sql`

- [ ] **Step 1: Write SQL**

Create `sql/monitor/top.sql`:
```sql
-- Real-time activity snapshot for top-like display
-- Output: pid, user, db, state, duration, query

SELECT
    pid,
    usename AS user,
    datname AS database,
    COALESCE(state, 'unknown') AS state,
    CASE
        WHEN state = 'idle' THEN '00:00:00'
        ELSE COALESCE(
            TO_CHAR(NOW() - query_start, 'HH24:MI:SS'),
            '00:00:00'
        )
    END AS duration,
    LEFT(COALESCE(query, ''), 60) AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY
    CASE state
        WHEN 'active' THEN 0
        WHEN 'idle in transaction' THEN 1
        WHEN 'idle' THEN 2
        ELSE 3
    END,
    query_start DESC NULLS LAST
LIMIT 20;
```

- [ ] **Step 2: Commit**

```bash
git add sql/monitor/top.sql
git commit -m "feat(monitor): add SQL for top command"
```

---

### Task 2: Create Command Script

**Files:**
- Create: `commands/monitor/top.sh`

- [ ] **Step 1: Write script**

Create `commands/monitor/top.sh`:
```bash
#!/bin/bash
# commands/monitor/top.sh - Interactive top-like display

# Default refresh interval in seconds
PGTOOL_TOP_INTERVAL="${PGTOOL_TOP_INTERVAL:-2}"

#==============================================================================
# Main Function
#==============================================================================

pgtool_monitor_top() {
    local -a opts=()
    local interval="$PGTOOL_TOP_INTERVAL"
    local running=true
    local paused=false

    # Parse parameters
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_monitor_top_help
                return 0
                ;;
            -i|--interval)
                shift
                interval="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validate interval
    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        pgtool_error "Invalid interval: $interval"
        return $EXIT_INVALID_ARGS
    fi

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "monitor" "top"); then
        pgtool_fatal "SQL file not found: monitor/top"
    fi

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Save terminal settings
    local old_stty
    old_stty=$(stty -g 2>/dev/null || echo "")

    # Setup terminal for non-blocking input
    if [[ -t 0 ]]; then
        stty -icanon -echo min 0 time 0 2>/dev/null || true
    fi

    # Clear screen once at start
    clear

    # Main display loop
    while $running; do
        if ! $paused; then
            # Get terminal size
            local rows cols
            read -r rows cols < <(stty size 2>/dev/null || echo "24 80")

            # Clear screen and move to top
            clear

            # Header
            echo "pgtool monitor top - $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Database: ${PGDATABASE:-$PGHOST} | Interval: ${interval}s | Press 'q' to quit, 'p' to pause, 'r' to refresh"
            echo ""

            # Execute query
            local result
            result=$(timeout "$PGTOOL_TIMEOUT" psql \
                "${PGTOOL_CONN_OPTS[@]}" \
                --file="$sql_file" \
                --pset=pager=off \
                --pset=format=aligned \
                --pset=border=1 \
                2>&1)

            if [[ $? -eq 0 ]]; then
                echo "$result"
            else
                echo "Error: $result"
            fi

            echo ""
            echo "Active: $(echo "$result" | grep -c "active") | Idle in transaction: $(echo "$result" | grep -c "idle in transaction") | Idle: $(echo "$result" | grep -c "idle")"
        else
            clear
            echo "PAUSED - Press 'p' to resume"
        fi

        # Wait for interval or keypress
        local waited=0
        while [[ $waited -lt $interval ]]; do
            if [[ -t 0 ]]; then
                local key
                key=$(dd bs=1 count=1 2>/dev/null)
                case "$key" in
                    q|Q)
                        running=false
                        break
                        ;;
                    p|P)
                        paused=!$paused
                        break
                        ;;
                    r|R)
                        break
                        ;;
                esac
            fi
            sleep 1
            ((waited++))
        done
    done

    # Restore terminal
    if [[ -n "$old_stty" ]]; then
        stty "$old_stty" 2>/dev/null || true
    fi

    clear
    pgtool_info "Monitor stopped"
    return $EXIT_SUCCESS
}

#==============================================================================
# Help Function
#==============================================================================

pgtool_monitor_top_help() {
    cat <<EOF
实时监控数据库活动 (top-like)

显示活动会话的实时视图，自动刷新。

用法: pgtool monitor top [选项]

选项:
  -h, --help          显示帮助
  -i, --interval SEC  刷新间隔秒数 (默认: 2)

交互命令:
  q    退出
  p    暂停/继续
  r    立即刷新

环境变量:
  PGTOOL_TOP_INTERVAL  默认刷新间隔

示例:
  pgtool monitor top
  pgtool monitor top --interval=5
EOF
}
```

- [ ] **Step 2: Make executable and verify**

```bash
chmod +x commands/monitor/top.sh
ls -la commands/monitor/top.sh
```

- [ ] **Step 3: Commit**

```bash
git add commands/monitor/top.sh
git commit -m "feat(monitor): add top command interactive implementation"
```

---

### Task 3: Register Command

**Files:**
- Modify: `commands/monitor/index.sh`

- [ ] **Step 1: Add to command list**

Edit `commands/monitor/index.sh`, add "top" to PGTOOL_MONITOR_COMMANDS:

```bash
PGTOOL_MONITOR_COMMANDS="connections:连接监控,queries:查询监控,replication:复制监控,top:实时活动监控"
```

- [ ] **Step 2: Add help text**

In `pgtool_monitor_help()` function, add:
```
  top             实时活动监控 (top-like)
```

- [ ] **Step 3: Commit**

```bash
git add commands/monitor/index.sh
git commit -m "feat(monitor): register top command"
```

---

### Task 4: Create Tests

**Files:**
- Create: `tests/test_monitor_top.sh`

- [ ] **Step 1: Write tests**

Create `tests/test_monitor_top.sh`:
```bash
#!/bin/bash
# tests/test_monitor_top.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

# Test: SQL file exists
test_sql_file_exists() {
    assert_true "[[ -f \"$PGTOOL_ROOT/sql/monitor/top.sql\" ]]"
}

# Test: Command script exists and is executable
test_command_script_exists() {
    assert_true "[[ -f \"$PGTOOL_ROOT/commands/monitor/top.sh\" ]]"
    assert_true "[[ -x \"$PGTOOL_ROOT/commands/monitor/top.sh\" ]]"
}

# Test: Command is registered
test_command_registered() {
    source "$PGTOOL_ROOT/commands/monitor/index.sh"
    assert_contains "$PGTOOL_MONITOR_COMMANDS" "top"
}

# Test: Help works
test_help_command() {
    local output
    output=$(cd "$PGTOOL_ROOT" && timeout 2 ./pgtool.sh monitor top --help 2>&1 || true)
    assert_contains "$output" "实时活动监控"
}

# Run tests
echo ""
echo "Monitor Top Tests:"
run_test "test_sql_file_exists" "SQL file exists"
run_test "test_command_script_exists" "Command script exists and executable"
run_test "test_command_registered" "Command registered"
run_test "test_help_command" "Help works"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x tests/test_monitor_top.sh
```

- [ ] **Step 3: Commit**

```bash
git add tests/test_monitor_top.sh
git commit -m "test(monitor): add tests for top command"
```

---

## Self-Review Checklist

- [ ] Spec coverage: All requirements from plan implemented
- [ ] Placeholder scan: No TODO, TBD, or incomplete steps remain
- [ ] Terminal handling: Proper cleanup on exit
- [ ] Interactive features: q/p/r keys work as documented
- [ ] Pattern compliance: Follows existing monitor command patterns

---

## Testing Commands

```bash
# Test help
./pgtool.sh monitor top --help

# Run the command (requires database)
./pgtool.sh monitor top
./pgtool.sh monitor top --interval=5

# Run tests
cd tests && ./run.sh test_monitor_top
```
