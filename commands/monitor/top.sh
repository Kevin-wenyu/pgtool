#!/bin/bash
# commands/monitor/top.sh - Real-time activity monitoring (top-like view)

# Main function: pgtool_monitor_top
pgtool_monitor_top() {
    local interval=2
    local limit=20
    local once=false
    local help=false
    local paused=false

    # Parse arguments
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
            -l|--limit)
                shift
                limit="$1"
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
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                # Global options, skip value
                shift
                shift
                ;;
            -*)
                pgtool_error "Unknown option: $1"
                pgtool_monitor_top_help
                return $EXIT_INVALID_ARGS
                ;;
            *)
                shift
                ;;
        esac
    done

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "monitor" "top"); then
        pgtool_fatal "SQL file not found: monitor/top"
    fi

    # Test connection
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Replace SQL parameters
    local sql
    sql=$(sed "s/:limit/${limit}/g" "$sql_file")

    # --once mode: execute once and exit
    if [[ "$once" == true ]]; then
        pgtool_monitor_top_once "$sql"
        return $?
    fi

    # Interactive mode: check TTY
    if [[ ! -t 1 ]]; then
        pgtool_error "Interactive mode requires a terminal (TTY)"
        pgtool_info "Use --once option to run in non-terminal environments"
        return $EXIT_INVALID_ARGS
    fi

    # Run interactive mode
    pgtool_monitor_top_interactive "$sql" "$interval" "$limit"
}

# Execute once mode
pgtool_monitor_top_once() {
    local sql="$1"
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --command="$sql" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL execution timeout (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL execution failed: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"
    return 0
}

# Interactive mode: real-time refresh with pause support
pgtool_monitor_top_interactive() {
    local sql="$1"
    local interval="$2"
    local limit="$3"
    local running=true
    local paused=false

    # Setup signal handlers
    cleanup() {
        running=false
        pgtool_monitor_cleanup
    }
    trap cleanup EXIT INT TERM

    # Hide cursor
    pgtool_monitor_hide_cursor

    # Clear screen
    pgtool_monitor_clear_screen

    # Refresh loop
    while [[ "$running" == true ]]; do
        pgtool_monitor_clear_screen
        pgtool_monitor_print_header "Activity Top (limit: $limit)" 80

        # Show pause status if paused
        if [[ "$paused" == true ]]; then
            printf "\n%b[PAUSED]%b\n" "$PGTOOL_MONITOR_COLOR_YELLOW" "$PGTOOL_MONITOR_COLOR_RESET"
        fi

        # Only execute query if not paused
        if [[ "$paused" == false ]]; then
            local result
            result=$(timeout "$PGTOOL_TIMEOUT" psql \
                "${PGTOOL_CONN_OPTS[@]}" \
                --command="$sql" \
                --pset=format=unaligned \
                --pset=fieldsep='|' \
                --pset=border=0 \
                --pset=header \
                --pset=pager=off \
                --quiet \
                2>&1)

            local exit_code=$?

            if [[ $exit_code -eq 124 ]]; then
                echo "Query timeout"
            elif [[ $exit_code -ne 0 ]]; then
                echo "Query failed: $result"
            else
                # Colorize output
                pgtool_monitor_top_colorize "$result"
            fi
        fi

        # Prompt line
        printf "\n%bq=quit, p=pause/resume%b\n" "$PGTOOL_MONITOR_COLOR_YELLOW" "$PGTOOL_MONITOR_COLOR_RESET"

        # Read key with timeout
        local key
        key=$(pgtool_monitor_read_key "$interval")

        # Handle key presses
        case "$key" in
            q|Q|$'\e'|$'\003'|$'\004')
                break
                ;;
            p|P)
                if [[ "$paused" == true ]]; then
                    paused=false
                else
                    paused=true
                fi
                ;;
        esac
    done

    # Cleanup (signal handler will also run)
    return 0
}

# Colorize output based on state and duration
pgtool_monitor_top_colorize() {
    local result="$1"
    local line_num=0

    # Read each line
    while IFS= read -r line; do
        ((line_num++))

        # First line is header
        if [[ $line_num -eq 1 ]]; then
            printf "%b%s%b\n" "$PGTOOL_MONITOR_COLOR_BOLD" "$line" "$PGTOOL_MONITOR_COLOR_RESET"
            continue
        fi

        # Empty lines or separator lines
        if [[ -z "$line" ]] || [[ "$line" == "("* ]]; then
            echo "$line"
            continue
        fi

        # Parse line data
        # Format: pid|user|database|state|duration|query
        local state
        state=$(echo "$line" | cut -d'|' -f4)

        local duration
        duration=$(echo "$line" | cut -d'|' -f5)

        # Get color based on state and duration
        local color
        color=$(pgtool_monitor_top_get_color "$state" "$duration")

        printf "%b%s%b\n" "$color" "$line" "$PGTOOL_MONITOR_COLOR_RESET"
    done <<< "$result"
}

# Get color based on state and duration
pgtool_monitor_top_get_color() {
    local state="$1"
    local duration="$2"

    # Normalize state
    state=$(echo "$state" | tr '[:upper:]' '[:lower:]')

    # Check for critical/warning states
    case "$state" in
        *idle*in*transaction*)
            echo "$PGTOOL_MONITOR_COLOR_YELLOW"
            return
            ;;
        blocked|waiting)
            echo "$PGTOOL_MONITOR_COLOR_RED"
            return
            ;;
    esac

    # Check duration thresholds
    if [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        if (( $(echo "$duration > 60" | bc -l 2>/dev/null || echo "0") )); then
            echo "$PGTOOL_MONITOR_COLOR_RED"
            return
        elif (( $(echo "$duration > 10" | bc -l 2>/dev/null || echo "0") )); then
            echo "$PGTOOL_MONITOR_COLOR_YELLOW"
            return
        fi
    fi

    # Normal states
    case "$state" in
        active)
            echo "$PGTOOL_MONITOR_COLOR_GREEN"
            ;;
        idle)
            echo "$PGTOOL_MONITOR_COLOR_BLUE"
            ;;
        *)
            echo "$PGTOOL_MONITOR_COLOR_RESET"
            ;;
    esac
}

# Help function
pgtool_monitor_top_help() {
    cat <<EOF
Real-time activity monitoring (top-like view)

Displays current database activity similar to Unix top command:
- PID, user, database name
- Connection state (active, idle, idle in transaction, etc.)
- Query duration in seconds
- SQL query (truncated to 60 characters)

Usage: pgtool monitor top [options]

Options:
  -h, --help          Show help
  -i, --interval SEC  Refresh interval in seconds (default: 2)
  -l, --limit NUM     Number of entries to display (default: 20)
  --once              Run once and exit (no interactive mode)
  --format FORMAT     Output format (table, json, csv)

Interactive Mode:
  Press 'q' to quit the monitor
  Press 'p' to pause/resume auto-refresh

Color Legend:
  Red     Duration > 60s or blocked/waiting
  Yellow  Duration > 10s or idle in transaction
  Green   Active query with normal duration
  Blue    Idle connections

Examples:
  pgtool monitor top                   # Interactive mode, 2 second refresh
  pgtool monitor top -i 1 -l 10       # 1 second refresh, show 10 entries
  pgtool monitor top --once           # Run once and exit
  pgtool monitor top --once --format=json
EOF
}
