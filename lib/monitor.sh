#!/bin/bash
# lib/monitor.sh - Terminal control utilities for real-time monitoring

# 必须先加载 core.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# ANSI Color Codes for Monitor Mode
#==============================================================================
readonly PGTOOL_MONITOR_COLOR_RESET='\033[0m'
readonly PGTOOL_MONITOR_COLOR_RED='\033[31m'
readonly PGTOOL_MONITOR_COLOR_YELLOW='\033[33m'
readonly PGTOOL_MONITOR_COLOR_GREEN='\033[32m'
readonly PGTOOL_MONITOR_COLOR_BLUE='\033[34m'
readonly PGTOOL_MONITOR_COLOR_BOLD='\033[1m'

#==============================================================================
# Cursor Control
#==============================================================================

# Hide cursor
pgtool_monitor_hide_cursor() {
    printf '\033[?25l'
}

# Show cursor
pgtool_monitor_show_cursor() {
    printf '\033[?25h'
}

#==============================================================================
# Screen Control
#==============================================================================

# Clear screen and move cursor to home position
pgtool_monitor_clear_screen() {
    printf '\033[2J\033[H'
}

# Move cursor to home position (top-left)
pgtool_monitor_move_cursor_home() {
    printf '\033[H'
}

# Get terminal size as "lines cols"
pgtool_monitor_terminal_size() {
    local lines cols
    # Try stty first, fall back to tput
    if [[ -t 0 ]]; then
        read -r lines cols < <(stty size 2>/dev/null)
    fi
    # Fallback if stty fails
    if [[ -z "$lines" || -z "$cols" ]]; then
        lines=${LINES:-24}
        cols=${COLUMNS:-80}
    fi
    echo "$lines $cols"
}

#==============================================================================
# Color Functions
#==============================================================================

# Get color based on state and query_time
# Usage: pgtool_monitor_color_for_state <state> [query_time]
# Returns color code via stdout
pgtool_monitor_color_for_state() {
    local state="${1:-}"
    local query_time="${2:-0}"

    # Normalize state
    state=$(echo "$state" | tr '[:upper:]' '[:lower:]')

    # Critical states
    case "$state" in
        critical|error|failed|dead|blocked)
            echo "$PGTOOL_MONITOR_COLOR_RED"
            return
            ;;
    esac

    # Warning states or long queries
    if [[ "$state" == "warning" || "$state" == "slow" || "$state" == "idle in transaction" ]]; then
        echo "$PGTOOL_MONITOR_COLOR_YELLOW"
        return
    fi

    # Check query time thresholds
    if [[ "$query_time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        if (( $(echo "$query_time > 300" | bc -l 2>/dev/null || echo "0") )); then
            echo "$PGTOOL_MONITOR_COLOR_RED"
            return
        elif (( $(echo "$query_time > 60" | bc -l 2>/dev/null || echo "0") )); then
            echo "$PGTOOL_MONITOR_COLOR_YELLOW"
            return
        fi
    fi

    # Normal/OK states
    case "$state" in
        ok|active|running|idle|success|normal)
            echo "$PGTOOL_MONITOR_COLOR_GREEN"
            ;;
        *)
            echo "$PGTOOL_MONITOR_COLOR_BLUE"
            ;;
    esac
}

# Get color based on replication lag in bytes
# Usage: pgtool_monitor_color_for_lag <lag_bytes>
# Returns color code via stdout
pgtool_monitor_color_for_lag() {
    local lag_bytes="${1:-0}"

    # Remove non-numeric characters
    lag_bytes=$(echo "$lag_bytes" | tr -cd '0-9')
    lag_bytes=${lag_bytes:-0}

    # Thresholds (in bytes)
    local critical_threshold=104857600   # 100MB
    local warning_threshold=10485760     # 10MB

    if [[ "$lag_bytes" -gt "$critical_threshold" ]]; then
        echo "$PGTOOL_MONITOR_COLOR_RED"
    elif [[ "$lag_bytes" -gt "$warning_threshold" ]]; then
        echo "$PGTOOL_MONITOR_COLOR_YELLOW"
    else
        echo "$PGTOOL_MONITOR_COLOR_GREEN"
    fi
}

#==============================================================================
# Utilities
#==============================================================================

# Cleanup function: show cursor and clear screen
pgtool_monitor_cleanup() {
    pgtool_monitor_show_cursor
    pgtool_monitor_clear_screen
}

# Read single key with optional timeout
# Usage: pgtool_monitor_read_key [timeout_seconds]
# Returns key via stdout, or empty if timeout
pgtool_monitor_read_key() {
    local timeout="${1:-}"
    local key=""

    # Save terminal settings
    local old_tty
    old_tty=$(stty -g 2>/dev/null)

    # Set terminal to raw mode
    stty -icanon -echo min 0 time 1 2>/dev/null || stty raw -echo 2>/dev/null

    # Read key with timeout if specified
    if [[ -n "$timeout" ]]; then
        # Convert seconds to deciseconds for stty time
        local deciseconds=$((timeout * 10))
        stty min 0 time "$deciseconds" 2>/dev/null || true
    fi

    # Read the key
    IFS= read -rs -d '' -n 1 key 2>/dev/null || true

    # Handle escape sequences (arrow keys, etc.)
    if [[ "$key" == $'\033' ]]; then
        local extra_key
        IFS= read -rs -d '' -n 2 extra_key 2>/dev/null || true
        key="${key}${extra_key}"
    fi

    # Restore terminal settings
    stty "$old_tty" 2>/dev/null || true

    echo "$key"
}

# Get current timestamp
pgtool_monitor_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Print formatted header
# Usage: pgtool_monitor_print_header <title> [width]
pgtool_monitor_print_header() {
    local title="$1"
    local width="${2:-80}"
    local timestamp
    timestamp=$(pgtool_monitor_timestamp)

    # Calculate padding
    local title_len=${#title}
    local ts_len=${#timestamp}
    local padding=$((width - title_len - ts_len - 4))

    # Ensure minimum padding
    if [[ $padding -lt 2 ]]; then
        padding=2
        width=$((title_len + ts_len + 6))
    fi

    # Build header line
    local left_pad=$((padding / 2))
    local right_pad=$((padding - left_pad))

    # Print header with colors
    printf "%b" "$PGTOOL_MONITOR_COLOR_BOLD"
    printf "%${width}s" "" | tr ' ' '='
    printf "\n"
    printf "%*s%s%*s%s%*s\n" 1 "" "$title" "$left_pad" "" "$timestamp" "$right_pad" ""
    printf "%${width}s" "" | tr ' ' '='
    printf "%b\n" "$PGTOOL_MONITOR_COLOR_RESET"
}

#==============================================================================
# Terminal State Management
#==============================================================================

# Save terminal state for later restoration
pgtool_monitor_save_state() {
    PGTOOL_MONITOR_OLD_TTY=$(stty -g 2>/dev/null || echo "")
    export PGTOOL_MONITOR_OLD_TTY
}

# Restore terminal state
pgtool_monitor_restore_state() {
    if [[ -n "${PGTOOL_MONITOR_OLD_TTY:-}" ]]; then
        stty "$PGTOOL_MONITOR_OLD_TTY" 2>/dev/null || true
        unset PGTOOL_MONITOR_OLD_TTY
    fi
}

# Setup monitor mode (hide cursor, clear screen)
pgtool_monitor_setup() {
    pgtool_monitor_save_state
    pgtool_monitor_hide_cursor
    pgtool_monitor_clear_screen
}

#==============================================================================
# Key Constants
#==============================================================================

# Special key constants
readonly PGTOOL_MONITOR_KEY_Q='q'
readonly PGTOOL_MONITOR_KEY_Q_UPPER='Q'
readonly PGTOOL_MONITOR_KEY_UP=$'\033[A'
readonly PGTOOL_MONITOR_KEY_DOWN=$'\033[B'
readonly PGTOOL_MONITOR_KEY_LEFT=$'\033[D'
readonly PGTOOL_MONITOR_KEY_RIGHT=$'\033[C'
readonly PGTOOL_MONITOR_KEY_ENTER=$'\n'
readonly PGTOOL_MONITOR_KEY_SPACE=' '
readonly PGTOOL_MONITOR_KEY_ESC=$'\033'
readonly PGTOOL_MONITOR_KEY_CTRL_C=$'\003'
readonly PGTOOL_MONITOR_KEY_CTRL_D=$'\004'

# Check if key is quit
pgtool_monitor_is_quit_key() {
    local key="$1"
    [[ "$key" == "$PGTOOL_MONITOR_KEY_Q" || \
       "$key" == "$PGTOOL_MONITOR_KEY_Q_UPPER" || \
       "$key" == "$PGTOOL_MONITOR_KEY_ESC" || \
       "$key" == "$PGTOOL_MONITOR_KEY_CTRL_C" || \
       "$key" == "$PGTOOL_MONITOR_KEY_CTRL_D" ]]
}
