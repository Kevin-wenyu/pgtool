# Monitor Command Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `monitor` command group with real-time PostgreSQL monitoring (like `top`) including queries, connections, and replication monitoring.

**Architecture:** Interactive terminal UI using ANSI escape sequences for screen control, non-blocking input handling for 'q' to quit, refresh loop with configurable interval. Color coding for states (red=slow queries, yellow=waiting).

**Tech Stack:** Bash, ANSI escape sequences, psql

---

## File Structure

| File | Type | Purpose |
|------|------|---------|
| `commands/monitor/index.sh` | Create | Command group index with PGTOOL_MONITOR_COMMANDS |
| `commands/monitor/queries.sh` | Create | Real-time query monitoring (main command) |
| `commands/monitor/connections.sh` | Create | Real-time connection monitoring |
| `commands/monitor/replication.sh` | Create | Real-time replication lag monitoring |
| `lib/monitor.sh` | Create | Terminal control utilities (clear, cursor, colors) |
| `sql/monitor/queries.sql` | Create | Active queries SQL template |
| `sql/monitor/connections.sql` | Create | Connection stats SQL template |
| `sql/monitor/replication.sql` | Create | Replication lag SQL template |
| `lib/cli.sh` | Modify | Add "monitor" to PGTOOL_GROUPS and pgtool_group_desc |
| `tests/test_monitor.sh` | Create | Unit tests for monitor utilities |

---

## Task 1: Create Monitor Library (lib/monitor.sh)

**Files:**
- Create: `lib/monitor.sh`

- [ ] **Step 1: Write terminal control functions**

```bash
#!/bin/bash
# lib/monitor.sh - Monitor utilities for terminal UI

# Hide cursor
pgtool_monitor_hide_cursor() {
    printf '\033[?25l'
}

# Show cursor
pgtool_monitor_show_cursor() {
    printf '\033[?25h'
}

# Clear screen and move to home
pgtool_monitor_clear_screen() {
    printf '\033[2J\033[H'
}

# Move cursor to top-left
pgtool_monitor_move_cursor_home() {
    printf '\033[H'
}

# Get terminal dimensions
pgtool_monitor_terminal_size() {
    local cols lines
    cols=$(tput cols 2>/dev/null || echo 80)
    lines=$(tput lines 2>/dev/null || echo 24)
    echo "${lines} ${cols}"
}

# Color codes
PGTOOL_MONITOR_COLOR_RESET='\033[0m'
PGTOOL_MONITOR_COLOR_RED='\033[31m'
PGTOOL_MONITOR_COLOR_YELLOW='\033[33m'
PGTOOL_MONITOR_COLOR_GREEN='\033[32m'
PGTOOL_MONITOR_COLOR_BLUE='\033[34m'
PGTOOL_MONITOR_COLOR_BOLD='\033[1m'

# Get color for query state
pgtool_monitor_color_for_state() {
    local state="$1"
    local query_time="${2:-0}"

    case "$state" in
        active)
            if [[ "$query_time" -gt 60 ]]; then
                echo -e "$PGTOOL_MONITOR_COLOR_RED"
            elif [[ "$query_time" -gt 10 ]]; then
                echo -e "$PGTOOL_MONITOR_COLOR_YELLOW"
            else
                echo -e "$PGTOOL_MONITOR_COLOR_GREEN"
            fi
            ;;
        idle*)
            echo -e "$PGTOOL_MONITOR_COLOR_BLUE"
            ;;
        *)
            echo -e "$PGTOOL_MONITOR_COLOR_RESET"
            ;;
    esac
}

# Get color for lag
pgtool_monitor_color_for_lag() {
    local lag_bytes="$1"

    if [[ "$lag_bytes" -gt 1073741824 ]]; then  # > 1GB
        echo -e "$PGTOOL_MONITOR_COLOR_RED"
    elif [[ "$lag_bytes" -gt 104857600 ]]; then  # > 100MB
        echo -e "$PGTOOL_MONITOR_COLOR_YELLOW"
    else
        echo -e "$PGTOOL_MONITOR_COLOR_GREEN"
    fi
}

# Cleanup function
pgtool_monitor_cleanup() {
    pgtool_monitor_show_cursor
    pgtool_monitor_clear_screen
}

# Read single keypress with timeout
pgtool_monitor_read_key() {
    local timeout="${1:-1}"
    local key=""

    # Save terminal settings
    local old_settings
    old_settings=$(stty -g 2>/dev/null)

    # Set raw mode
    stty -echo -icanon time 0 min 0 2>/dev/null || true

    # Read with timeout
    if IFS= read -rs -t "$timeout" -n 1 key 2>/dev/null; then
        echo "$key"
    fi

    # Restore terminal settings
    stty "$old_settings" 2>/dev/null || true
}

# Format timestamp
pgtool_monitor_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Print header
pgtool_monitor_print_header() {
    local title="$1"
    local interval="$2"
    local extra="${3:-}"

    echo -e "${PGTOOL_MONITOR_COLOR_BOLD}=== $title | $(pgtool_monitor_timestamp) | Interval: ${interval}s | Press 'q' to quit ===${PGTOOL_MONITOR_COLOR_RESET}"
    [[ -n "$extra" ]] && echo "$extra"
    echo
}
```

- [ ] **Step 2: Add library to pgtool.sh**

修改 `pgtool.sh` 在加载其他 lib 文件后添加:

```bash
# 加载核心模块
source "$PGTOOL_SCRIPT_DIR/lib/core.sh"
source "$PGTOOL_SCRIPT_DIR/lib/log.sh"
source "$PGTOOL_SCRIPT_DIR/lib/util.sh"
source "$PGTOOL_SCRIPT_DIR/lib/output.sh"
source "$PGTOOL_SCRIPT_DIR/lib/pg.sh"
source "$PGTOOL_SCRIPT_DIR/lib/plugin.sh"
source "$PGTOOL_SCRIPT_DIR/lib/cli.sh"
source "$PGTOOL_SCRIPT_DIR/lib/monitor.sh"  # Add this line
```

- [ ] **Step 3: Commit**

```bash
git add lib/monitor.sh pgtool.sh
git commit -m "feat(monitor): add monitor utility library with terminal control"
```

---

## Task 2: Create SQL Templates

**Files:**
- Create: `sql/monitor/queries.sql`
- Create: `sql/monitor/connections.sql`
- Create: `sql/monitor/replication.sql`

- [ ] **Step 1: Write queries.sql**

```sql
-- sql/monitor/queries.sql
-- Real-time active query monitoring
-- Parameters: :limit

SELECT
    pid,
    usename AS username,
    datname AS database,
    client_addr::text AS client,
    state,
    COALESCE(EXTRACT(EPOCH FROM (now() - query_start))::int, 0) AS query_time,
    LEFT(query, 100) AS query_text
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
  AND backend_type = 'client backend'
ORDER BY query_start DESC NULLS LAST
LIMIT :limit;
```

- [ ] **Step 2: Write connections.sql**

```sql
-- sql/monitor/connections.sql
-- Real-time connection monitoring
-- Parameters: none

SELECT
    datname AS database,
    state,
    COUNT(*) AS count,
    COALESCE(SUM(EXTRACT(EPOCH FROM (now() - backend_start)))::bigint / COUNT(*), 0) AS avg_conn_time
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY datname, state
ORDER BY count DESC, datname;
```

- [ ] **Step 3: Write replication.sql**

```sql
-- sql/monitor/replication.sql
-- Real-time replication lag monitoring
-- Parameters: none

SELECT
    client_addr AS replica,
    state,
    sent_lsn::text,
    flush_lsn::text,
    pg_wal_lsn_diff(sent_lsn, flush_lsn) AS lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, flush_lsn)) AS lag_size,
    reply_time
FROM pg_stat_replication
ORDER BY lag_bytes DESC;
```

- [ ] **Step 4: Commit**

```bash
git add sql/monitor/
git commit -m "feat(monitor): add SQL templates for query, connection, and replication monitoring"
```

---

## Task 3: Create Command Group Index

**Files:**
- Create: `commands/monitor/index.sh`

- [ ] **Step 1: Write index.sh**

```bash
#!/bin/bash
# commands/monitor/index.sh - monitor command group index

# Command list: "command:description"
PGTOOL_MONITOR_COMMANDS="queries:实时监控活跃查询,connections:实时监控连接数,replication:实时监控复制延迟"

# Display help
pgtool_monitor_help() {
    cat <<EOF
监控类命令 - 实时数据库监控

可用命令:
  queries      实时监控活跃查询 (类似 top)
  connections  实时监控连接统计
  replication  实时监控复制延迟

选项:
  -h, --help           显示帮助
  -i, --interval SEC   刷新间隔秒数 (默认: 2)
  -l, --limit NUM      显示行数限制 (默认: 20)
      --once           只执行一次，不进入刷新循环

使用 'pgtool monitor <命令> --help' 查看具体命令帮助

示例:
  pgtool monitor queries              # 交互式监控查询
  pgtool monitor queries --once       # 单次执行
  pgtool monitor queries -i 5 -l 50   # 5秒刷新，显示50行
  pgtool monitor connections --once --format=json
  pgtool monitor replication -i 10
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/monitor/index.sh
git commit -m "feat(monitor): add monitor command group index"
```

---

## Task 4: Implement Monitor Queries Command

**Files:**
- Create: `commands/monitor/queries.sh`

- [ ] **Step 1: Write queries.sh**

```bash
#!/bin/bash
# commands/monitor/queries.sh - Real-time query monitoring

#==============================================================================
# Default values
#==============================================================================

PGTOOL_MONITOR_INTERVAL="${PGTOOL_MONITOR_INTERVAL:-2}"
PGTOOL_MONITOR_LIMIT="${PGTOOL_MONITOR_LIMIT:-20}"

#==============================================================================
# Main function
#==============================================================================

pgtool_monitor_queries() {
    local -a opts=()
    local -a args=()
    local interval="$PGTOOL_MONITOR_INTERVAL"
    local limit="$PGTOOL_MONITOR_LIMIT"
    local once=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_monitor_queries_help
                return 0
                ;;
            -i|--interval)
                shift
                interval="$1"
                if ! is_int "$interval" || [[ "$interval" -lt 1 ]]; then
                    pgtool_error "刷新间隔必须是正整数"
                    return $EXIT_INVALID_ARGS
                fi
                shift
                ;;
            -l|--limit)
                shift
                limit="$1"
                if ! is_int "$limit" || [[ "$limit" -lt 1 ]]; then
                    pgtool_error "行数限制必须是正整数"
                    return $EXIT_INVALID_ARGS
                fi
                shift
                ;;
            --once)
                once=true
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

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "monitor" "queries"); then
        pgtool_fatal "SQL文件未找到: monitor/queries"
    fi

    # If --once mode, just execute and exit
    if [[ "$once" == true ]]; then
        local format_args
        format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

        timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            --variable="limit=$limit" \
            --pset=pager=off \
            $format_args \
            2>&1
        return $?
    fi

    # Interactive mode - check if terminal is TTY
    if [[ ! -t 1 ]]; then
        pgtool_error "交互模式需要TTY终端，请使用 --once 选项"
        return $EXIT_INVALID_ARGS
    fi

    # Setup signal handlers
    local running=true
    cleanup() {
        running=false
        pgtool_monitor_cleanup
    }
    trap cleanup EXIT INT TERM

    # Hide cursor
    pgtool_monitor_hide_cursor

    # Main refresh loop
    while [[ "$running" == true ]]; do
        # Clear screen
        pgtool_monitor_clear_screen

        # Print header
        pgtool_monitor_print_header "Query Monitor" "$interval" "Limit: $limit rows"

        # Execute query
        local result
        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            --variable="limit=$limit" \
            --pset=pager=off \
            --pset=footer=off \
            2>&1)

        if [[ $? -ne 0 ]]; then
            echo "Error: $result"
        else
            # Colorize output based on query time
            local line
            local header_printed=false
            while IFS= read -r line; do
                if [[ "$header_printed" == false ]]; then
                    # Print header as-is
                    echo "$line"
                    header_printed=true
                elif [[ -z "$line" ]]; then
                    continue
                elif [[ "$line" =~ ^[0-9]+ ]]; then
                    # Parse line for coloring
                    local query_time
                    query_time=$(echo "$line" | awk -F'|' '{print $6}' | tr -d ' ')
                    if [[ "$query_time" -gt 60 ]]; then
                        echo -e "${PGTOOL_MONITOR_COLOR_RED}${line}${PGTOOL_MONITOR_COLOR_RESET}"
                    elif [[ "$query_time" -gt 10 ]]; then
                        echo -e "${PGTOOL_MONITOR_COLOR_YELLOW}${line}${PGTOOL_MONITOR_COLOR_RESET}"
                    else
                        echo -e "${PGTOOL_MONITOR_COLOR_GREEN}${line}${PGTOOL_MONITOR_COLOR_RESET}"
                    fi
                else
                    echo "$line"
                fi
            done <<< "$result"
        fi

        # Check for keypress
        local key
        key=$(pgtool_monitor_read_key "$interval")
        if [[ "$key" == "q" ]]; then
            break
        fi
    done

    # Cleanup
    cleanup
    return $EXIT_SUCCESS
}

# Help function
pgtool_monitor_queries_help() {
    cat <<EOF
实时监控活跃查询

显示当前正在执行的查询，类似 Linux 的 top 命令。
高亮显示长时间运行的查询（黄色>10s，红色>60s）。

用法: pgtool monitor queries [选项]

选项:
  -h, --help              显示帮助
  -i, --interval SEC      刷新间隔秒数 (默认: 2)
  -l, --limit NUM         显示行数限制 (默认: 20)
      --once              只执行一次，不进入交互模式
      --format FORMAT     输出格式 (table|json|csv|tsv，仅用于 --once)

交互模式快捷键:
  q                       退出监控

示例:
  pgtool monitor queries
  pgtool monitor queries -i 5 -l 50
  pgtool monitor queries --once --format=json
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/monitor/queries.sh
git commit -m "feat(monitor): add queries command for real-time query monitoring"
```

---

## Task 5: Implement Monitor Connections Command

**Files:**
- Create: `commands/monitor/connections.sh`

- [ ] **Step 1: Write connections.sh**

```bash
#!/bin/bash
# commands/monitor/connections.sh - Real-time connection monitoring

#==============================================================================
# Default values
#==============================================================================

PGTOOL_MONITOR_INTERVAL="${PGTOOL_MONITOR_INTERVAL:-2}"

#==============================================================================
# Main function
#==============================================================================

pgtool_monitor_connections() {
    local -a opts=()
    local -a args=()
    local interval="$PGTOOL_MONITOR_INTERVAL"
    local once=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_monitor_connections_help
                return 0
                ;;
            -i|--interval)
                shift
                interval="$1"
                if ! is_int "$interval" || [[ "$interval" -lt 1 ]]; then
                    pgtool_error "刷新间隔必须是正整数"
                    return $EXIT_INVALID_ARGS
                fi
                shift
                ;;
            --once)
                once=true
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

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "monitor" "connections"); then
        pgtool_fatal "SQL文件未找到: monitor/connections"
    fi

    # If --once mode
    if [[ "$once" == true ]]; then
        local format_args
        format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

        timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            --pset=pager=off \
            $format_args \
            2>&1
        return $?
    fi

    # Interactive mode
    if [[ ! -t 1 ]]; then
        pgtool_error "交互模式需要TTY终端，请使用 --once 选项"
        return $EXIT_INVALID_ARGS
    fi

    # Setup signal handlers
    local running=true
    cleanup() {
        running=false
        pgtool_monitor_cleanup
    }
    trap cleanup EXIT INT TERM

    # Hide cursor
    pgtool_monitor_hide_cursor

    # Main refresh loop
    while [[ "$running" == true ]]; do
        pgtool_monitor_clear_screen

        # Print header
        pgtool_monitor_print_header "Connection Monitor" "$interval"

        # Execute query
        local result
        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            --pset=pager=off \
            --pset=footer=off \
            2>&1)

        if [[ $? -ne 0 ]]; then
            echo "Error: $result"
        else
            # Calculate totals
            local total_conn
            total_conn=$(echo "$result" | tail -n +4 | grep -c '^[a-z]' 2>/dev/null || echo 0)

            # Display results
            echo "$result"
            echo
            echo -e "${PGTOOL_MONITOR_COLOR_BOLD}Total connections: $total_conn${PGTOOL_MONITOR_COLOR_RESET}"
        fi

        # Check for keypress
        local key
        key=$(pgtool_monitor_read_key "$interval")
        if [[ "$key" == "q" ]]; then
            break
        fi
    done

    cleanup
    return $EXIT_SUCCESS
}

# Help function
pgtool_monitor_connections_help() {
    cat <<EOF
实时监控数据库连接

按数据库和状态分组显示连接统计。

用法: pgtool monitor connections [选项]

选项:
  -h, --help              显示帮助
  -i, --interval SEC      刷新间隔秒数 (默认: 2)
      --once              只执行一次，不进入交互模式
      --format FORMAT     输出格式 (仅用于 --once)

交互模式快捷键:
  q                       退出监控

示例:
  pgtool monitor connections
  pgtool monitor connections -i 5
  pgtool monitor connections --once --format=json
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/monitor/connections.sh
git commit -m "feat(monitor): add connections command for real-time connection monitoring"
```

---

## Task 6: Implement Monitor Replication Command

**Files:**
- Create: `commands/monitor/replication.sh`

- [ ] **Step 1: Write replication.sh**

```bash
#!/bin/bash
# commands/monitor/replication.sh - Real-time replication lag monitoring

#==============================================================================
# Default values
#==============================================================================

PGTOOL_MONITOR_INTERVAL="${PGTOOL_MONITOR_INTERVAL:-2}"

#==============================================================================
# Main function
#==============================================================================

pgtool_monitor_replication() {
    local -a opts=()
    local -a args=()
    local interval="$PGTOOL_MONITOR_INTERVAL"
    local once=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_monitor_replication_help
                return 0
                ;;
            -i|--interval)
                shift
                interval="$1"
                if ! is_int "$interval" || [[ "$interval" -lt 1 ]]; then
                    pgtool_error "刷新间隔必须是正整数"
                    return $EXIT_INVALID_ARGS
                fi
                shift
                ;;
            --once)
                once=true
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

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Check if this is a primary (has replication connections)
    local is_primary
    is_primary=$(pgtool_pg_query_one "SELECT EXISTS(SELECT 1 FROM pg_stat_replication)")

    if [[ "$is_primary" != "t" ]]; then
        pgtool_error "当前数据库不是主库或未配置流复制"
        return $EXIT_GENERAL_ERROR
    fi

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "monitor" "replication"); then
        pgtool_fatal "SQL文件未找到: monitor/replication"
    fi

    # If --once mode
    if [[ "$once" == true ]]; then
        local format_args
        format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

        timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            --pset=pager=off \
            $format_args \
            2>&1
        return $?
    fi

    # Interactive mode
    if [[ ! -t 1 ]]; then
        pgtool_error "交互模式需要TTY终端，请使用 --once 选项"
        return $EXIT_INVALID_ARGS
    fi

    # Setup signal handlers
    local running=true
    cleanup() {
        running=false
        pgtool_monitor_cleanup
    }
    trap cleanup EXIT INT TERM

    # Hide cursor
    pgtool_monitor_hide_cursor

    # Main refresh loop
    while [[ "$running" == true ]]; do
        pgtool_monitor_clear_screen

        # Print header
        pgtool_monitor_print_header "Replication Monitor" "$interval"

        # Execute query
        local result
        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            --pset=pager=off \
            --pset=footer=off \
            2>&1)

        if [[ $? -ne 0 ]]; then
            echo "Error: $result"
        elif echo "$result" | grep -q "(0 rows)"; then
            echo "No replication connections found"
        else
            # Display with color coding for lag
            local line
            local header_printed=false
            local separator_printed=false
            while IFS= read -r line; do
                if [[ "$header_printed" == false ]]; then
                    echo "$line"
                    header_printed=true
                elif [[ "$separator_printed" == false ]] && [[ "$line" =~ ^-+ ]]; then
                    echo "$line"
                    separator_printed=true
                elif [[ -z "$line" ]]; then
                    continue
                else
                    # Parse lag_bytes for coloring
                    local lag_bytes
                    lag_bytes=$(echo "$line" | awk -F'|' '{print $5}' | tr -d ' ')
                    if [[ "$lag_bytes" =~ ^[0-9]+$ ]]; then
                        if [[ "$lag_bytes" -gt 1073741824 ]]; then
                            echo -e "${PGTOOL_MONITOR_COLOR_RED}${line}${PGTOOL_MONITOR_COLOR_RESET}"
                        elif [[ "$lag_bytes" -gt 104857600 ]]; then
                            echo -e "${PGTOOL_MONITOR_COLOR_YELLOW}${line}${PGTOOL_MONITOR_COLOR_RESET}"
                        else
                            echo -e "${PGTOOL_MONITOR_COLOR_GREEN}${line}${PGTOOL_MONITOR_COLOR_RESET}"
                        fi
                    else
                        echo "$line"
                    fi
                fi
            done <<< "$result"
        fi

        # Check for keypress
        local key
        key=$(pgtool_monitor_read_key "$interval")
        if [[ "$key" == "q" ]]; then
            break
        fi
    done

    cleanup
    return $EXIT_SUCCESS
}

# Help function
pgtool_monitor_replication_help() {
    cat <<EOF
实时监控复制延迟

显示流复制连接的延迟情况。
高亮显示延迟过大的副本（黄色>100MB，红色>1GB）。

用法: pgtool monitor replication [选项]

选项:
  -h, --help              显示帮助
  -i, --interval SEC      刷新间隔秒数 (默认: 2)
      --once              只执行一次，不进入交互模式
      --format FORMAT     输出格式 (仅用于 --once)

交互模式快捷键:
  q                       退出监控

示例:
  pgtool monitor replication
  pgtool monitor replication -i 10
  pgtool monitor replication --once --format=json

注意:
  此命令必须在主库上执行
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/monitor/replication.sh
git commit -m "feat(monitor): add replication command for real-time replication monitoring"
```

---

## Task 7: Register Monitor Command Group

**Files:**
- Modify: `lib/cli.sh`

- [ ] **Step 1: Add monitor to PGTOOL_GROUPS**

```bash
# Line 15: Change from:
PGTOOL_GROUPS=("check" "stat" "admin" "analyze" "plugin")
# To:
PGTOOL_GROUPS=("check" "stat" "admin" "analyze" "plugin" "monitor")
```

- [ ] **Step 2: Add monitor case to pgtool_group_desc**

```bash
# After line 25, add:
        monitor) echo "实时监控 - 实时监控数据库活动" ;;
```

- [ ] **Step 3: Commit**

```bash
git add lib/cli.sh
git commit -m "feat(monitor): register monitor command group in CLI dispatcher"
```

---

## Task 8: Create Tests

**Files:**
- Create: `tests/test_monitor.sh`

- [ ] **Step 1: Write test file**

```bash
#!/bin/bash
# tests/test_monitor.sh - Monitor module tests

# Load test framework
source "$TEST_DIR/test_runner.sh"

#==============================================================================
# Setup
#==============================================================================

setup_monitor_tests() {
    # Ensure lib is loaded
    if ! type pgtool_monitor_hide_cursor &>/dev/null; then
        source "$PGTOOL_ROOT/lib/monitor.sh" 2>/dev/null || true
    fi
}

#==============================================================================
# Tests
#==============================================================================

test_monitor_color_for_state() {
    # Test active with different times
    local color

    color=$(pgtool_monitor_color_for_state "active" 5)
    assert_contains "$color" "32"  # Green

    color=$(pgtool_monitor_color_for_state "active" 30)
    assert_contains "$color" "33"  # Yellow

    color=$(pgtool_monitor_color_for_state "active" 120)
    assert_contains "$color" "31"  # Red

    # Test idle states
    color=$(pgtool_monitor_color_for_state "idle" 0)
    assert_contains "$color" "34"  # Blue
}

test_monitor_color_for_lag() {
    local color

    color=$(pgtool_monitor_color_for_lag 10485760)  # 10MB
    assert_contains "$color" "32"  # Green

    color=$(pgtool_monitor_color_for_lag 209715200)  # 200MB
    assert_contains "$color" "33"  # Yellow

    color=$(pgtool_monitor_color_for_lag 2147483648)  # 2GB
    assert_contains "$color" "31"  # Red
}

test_monitor_commands_exist() {
    # Check command files exist
    assert_true "[[ -f $PGTOOL_ROOT/commands/monitor/index.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/monitor/queries.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/monitor/connections.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/monitor/replication.sh ]]"
}

test_monitor_sql_files_exist() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/monitor/queries.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/sql/monitor/connections.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/sql/monitor/replication.sql ]]"
}

test_monitor_registered_in_cli() {
    # Check if monitor is in PGTOOL_GROUPS
    assert_contains "${PGTOOL_GROUPS[*]}" "monitor"
}

#==============================================================================
# Run tests
#==============================================================================

setup_monitor_tests
run_test "monitor_color_for_state" test_monitor_color_for_state
run_test "monitor_color_for_lag" test_monitor_color_for_lag
run_test "monitor_commands_exist" test_monitor_commands_exist
run_test "monitor_sql_files_exist" test_monitor_sql_files_exist
run_test "monitor_registered" test_monitor_registered_in_cli
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_monitor.sh
git commit -m "test(monitor): add unit tests for monitor command group"
```

---

## Task 9: Integration Test

- [ ] **Step 1: Test monitor help**

```bash
./pgtool.sh monitor --help
```

Expected output: Shows monitor command group help with queries, connections, replication listed.

- [ ] **Step 2: Test queries --once mode**

```bash
./pgtool.sh monitor queries --once
```

Expected: Shows active queries (or empty if none).

- [ ] **Step 3: Test connections --once mode**

```bash
./pgtool.sh monitor connections --once
```

Expected: Shows connection stats.

- [ ] **Step 4: Test JSON output**

```bash
./pgtool.sh monitor queries --once --format=json
```

Expected: JSON formatted output.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat(monitor): complete monitor command group implementation"
```

---

## Spec Coverage Check

| Requirement | Task | Status |
|-------------|------|--------|
| Real-time query monitoring | Task 4 | ✓ |
| Real-time connection monitoring | Task 5 | ✓ |
| Real-time replication monitoring | Task 6 | ✓ |
| Interactive mode with 'q' to quit | Tasks 4-6 | ✓ |
| --once mode for scripting | Tasks 4-6 | ✓ |
| --interval option | Tasks 4-6 | ✓ |
| --limit option | Task 4 | ✓ |
| Color coding (red/yellow/green) | Tasks 1, 4, 6 | ✓ |
| Signal handling (SIGINT cleanup) | Tasks 4-6 | ✓ |
| SQL separation | Task 2 | ✓ |
| Command registration | Task 7 | ✓ |
| Tests | Tasks 8-9 | ✓ |

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-02-monitor-command-group.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
