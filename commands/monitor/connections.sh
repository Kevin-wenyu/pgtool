#!/bin/bash
# commands/monitor/connections.sh - Real-time connection monitoring

# Main function: pgtool_monitor_connections
pgtool_monitor_connections() {
    local interval=2
    local once=false
    local help=false

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
                pgtool_monitor_connections_help
                return $EXIT_INVALID_ARGS
                ;;
            *)
                shift
                ;;
        esac
    done

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "monitor" "connections"); then
        pgtool_fatal "SQL file not found: monitor/connections"
    fi

    # Test connection
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # --once mode: execute once and exit
    if [[ "$once" == true ]]; then
        pgtool_monitor_connections_once "$sql_file"
        return $?
    fi

    # Interactive mode: check TTY
    if [[ ! -t 1 ]]; then
        pgtool_error "Interactive mode requires a terminal (TTY)"
        pgtool_info "Use --once option to run in non-terminal environments"
        return $EXIT_INVALID_ARGS
    fi

    # Run interactive mode
    pgtool_monitor_connections_interactive "$sql_file" "$interval"
}

# Execute once mode
pgtool_monitor_connections_once() {
    local sql_file="$1"
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
        pgtool_error "SQL execution timeout (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL execution failed: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"
    return 0
}

# Interactive mode: real-time refresh
pgtool_monitor_connections_interactive() {
    local sql_file="$1"
    local interval="$2"
    local running=true

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
        pgtool_monitor_print_header "Connection Monitor" "$interval"

        # Execute query
        local result
        result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            --pset=format=aligned \
            --pset=border=2 \
            --pset=pager=off \
            --pset=header=on \
            2>&1)

        local exit_code=$?

        if [[ $exit_code -eq 124 ]]; then
            echo "Query timeout"
        elif [[ $exit_code -ne 0 ]]; then
            echo "Query failed: $result"
        else
            # Display results with colorization
            pgtool_monitor_connections_colorize "$result"
        fi

        # Calculate total connections
        local total
        total=$(echo "$result" | tail -n +4 | head -n -2 | awk -F'|' '{sum+=$3} END {print sum+0}')

        # Show total
        echo
        echo -e "${PGTOOL_MONITOR_COLOR_BOLD}Total connections: ${total:-0}${PGTOOL_MONITOR_COLOR_RESET}"

        # Read keypress with timeout
        local key
        key=$(pgtool_monitor_read_key "$interval")

        # Check for quit key
        if pgtool_monitor_is_quit_key "$key"; then
            break
        fi
    done

    # Cleanup (signal handler will also run)
    return 0
}

# Colorize connections output
pgtool_monitor_connections_colorize() {
    local result="$1"
    local line_num=0

    # Read each line
    while IFS= read -r line; do
        ((line_num++))

        # First 3 lines are header/separator
        if [[ $line_num -le 3 ]]; then
            printf "%b%s%b\n" "$PGTOOL_MONITOR_COLOR_BOLD" "$line" "$PGTOOL_MONITOR_COLOR_RESET"
            continue
        fi

        # Empty lines or separator lines
        if [[ -z "$line" ]] || [[ "$line" == "("* ]]; then
            echo "$line"
            continue
        fi

        # Parse row data: datname|state|count|avg_conn_time
        local state
        state=$(echo "$line" | cut -d'|' -f2 | tr -d ' ')

        local count
        count=$(echo "$line" | cut -d'|' -f3 | tr -d ' ')

        # Get color based on state and count
        local color
        color=$(pgtool_monitor_connections_get_color "$state" "$count")

        printf "%b%s%b\n" "$color" "$line" "$PGTOOL_MONITOR_COLOR_RESET"
    done <<< "$result"
}

# Get color based on connection state and count
pgtool_monitor_connections_get_color() {
    local state="$1"
    local count="${2:-0}"

    # Remove non-numeric characters
    count=$(echo "$count" | tr -cd '0-9')
    count=${count:-0}

    # Critical: high connection count
    if [[ "$count" -gt 100 ]]; then
        echo "$PGTOOL_MONITOR_COLOR_RED"
        return
    fi

    # Warning states
    case "$state" in
        *idle*in*transaction*)
            echo "$PGTOOL_MONITOR_COLOR_YELLOW"
            return
            ;;
    esac

    # Normal states
    echo "$PGTOOL_MONITOR_COLOR_GREEN"
}

# Help function
pgtool_monitor_connections_help() {
    cat <<EOF
Real-time connection monitoring

Displays connection statistics by database and state:
- Database name
- Connection state (active, idle, idle in transaction, etc.)
- Connection count per state
- Average connection time

Usage: pgtool monitor connections [options]

Options:
  -h, --help          Show help
  -i, --interval SEC  Refresh interval in seconds (default: 2)
  --once              Run once and exit (no interactive mode)
  --format FORMAT     Output format (table, json, csv)

Interactive Mode:
  Press 'q' to quit the monitor

Color Legend:
  Red     > 100 connections (high load)
  Yellow  Idle in transaction (potential issue)
  Green   Normal state

Examples:
  pgtool monitor connections              # Interactive mode, 2 second refresh
  pgtool monitor connections -i 5         # 5 second refresh interval
  pgtool monitor connections --once       # Run once and exit
  pgtool monitor connections --once --format=json
EOF
}
