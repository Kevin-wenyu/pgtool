#!/bin/bash
# lib/config_rules.sh - PostgreSQL configuration best practice rules

# 必须先加载 core.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# Configuration Best Practice Rules
# Format: name|category|check_type|threshold|recommendation|severity
#
# check_type: range, min, max, exact, bool, regex
# severity: INFO, WARN, CRITICAL
#==============================================================================

#------------------------------------------------------------------------------
# Memory Rules
#------------------------------------------------------------------------------
pgtool_config_rules_memory() {
    cat << 'EOF'
shared_buffers|memory|range|25%|Set to 25% of total RAM for OLTP workloads|WARN
effective_cache_size|memory|range|50%|Set to 50% of total RAM (OS file cache estimate)|WARN
work_mem|memory|range|256MB|Base: 256MB, divide by max_connections for heavy workloads|WARN
maintenance_work_mem|memory|min|1GB|Set high for vacuum, index creation (max 2GB)|WARN
huge_pages|memory|bool|try|Enable huge pages for better memory performance|INFO
EOF
}

#------------------------------------------------------------------------------
# Connection Rules
#------------------------------------------------------------------------------
pgtool_config_rules_connections() {
    cat << 'EOF'
max_connections|connections|max|200|Keep low (use connection pooling); increase only if needed|WARN
superuser_reserved_connections|connections|min|3|Reserve connections for superuser|INFO
ssl|connections|bool|on|Enable SSL for secure connections|CRITICAL
ssl_min_protocol_version|connections|exact|TLSv1.2|Use modern TLS versions|WARN
EOF
}

#------------------------------------------------------------------------------
# WAL Rules
#------------------------------------------------------------------------------
pgtool_config_rules_wal() {
    cat << 'EOF'
wal_level|wal|exact|replica|Use 'replica' or higher for replication|WARN
wal_buffers|wal|min|16MB|Large enough for burst writes|INFO
max_wal_size|wal|min|4GB|Set high to reduce checkpoint frequency|WARN
min_wal_size|wal|min|1GB|Keep recent WAL for crash recovery speed|INFO
wal_compression|wal|bool|on|Compress WAL to reduce I/O|INFO
archive_mode|wal|bool|on|Enable for point-in-time recovery|WARN
archive_command|wal|regex|^[^;]+$|Archive command must be safe|WARN
wal_writer_delay|wal|max|200ms|Balance durability vs performance|INFO
wal_init_zero|wal|bool|off|Disable zero-fill for faster WAL creation (Linux)|INFO
wal_recycle|wal|bool|on|Recycle WAL files for better performance|INFO
EOF
}

#------------------------------------------------------------------------------
# Vacuum Rules
#------------------------------------------------------------------------------
pgtool_config_rules_vacuum() {
    cat << 'EOF'
autovacuum|vacuum|bool|on|Enable autovacuum - do not disable|CRITICAL
autovacuum_max_workers|vacuum|range|3|Balance with maintenance_work_mem|WARN
autovacuum_naptime|vacuum|max|60s|Check frequently for busy databases|INFO
autovacuum_vacuum_scale_factor|vacuum|max|0.2|Lower for high-churn tables|WARN
autovacuum_analyze_scale_factor|vacuum|max|0.1|Lower for accurate statistics|INFO
vacuum_freeze_min_age|vacuum|max|50000000|Prevent transaction ID wraparound issues|WARN
EOF
}

#------------------------------------------------------------------------------
# Replication Rules
#------------------------------------------------------------------------------
pgtool_config_rules_replication() {
    cat << 'EOF'
max_wal_senders|replication|min|3|Enough for replicas and backups|WARN
max_replication_slots|replication|min|3|Match max_wal_senders|INFO
wal_sender_timeout|replication|min|60s|Timeout for replication connections|INFO
hot_standby|replication|bool|on|Enable for read replicas|WARN
hot_standby_feedback|replication|bool|on|Prevent vacuum conflicts on replicas|INFO
max_standby_streaming_delay|replication|max|30s|Limit replay delay|INFO
EOF
}

#------------------------------------------------------------------------------
# Logging Rules
#------------------------------------------------------------------------------
pgtool_config_rules_logging() {
    cat << 'EOF'
logging_collector|logging|bool|on|Enable file logging|WARN
log_destination|logging|regex|stderr,csvlog|Log to stderr and CSV|INFO
log_checkpoints|logging|bool|on|Log checkpoint activity|WARN
log_connections|logging|bool|on|Log connections for audit|INFO
log_disconnections|logging|bool|on|Log disconnections for audit|INFO
log_lock_waits|logging|bool|on|Detect lock contention|WARN
log_temp_files|logging|max|0|Log all temp files (0=unlimited)|INFO
log_autovacuum_min_duration|logging|max|0|Log all autovacuum activity (0=all)|INFO
log_min_duration_statement|logging|max|1000|Log slow queries (>1s)|WARN
log_line_prefix|logging|regex|%t \[%p\]: \[%l-1\] user=%u,db=%d,app=%a,client=%h|Include timestamp, pid, user, database|INFO
log_rotation_age|logging|max|1d|Rotate logs daily|INFO
log_rotation_size|logging|max|100MB|Rotate large logs|INFO
EOF
}

#------------------------------------------------------------------------------
# Planner Rules
#------------------------------------------------------------------------------
pgtool_config_rules_planner() {
    cat << 'EOF'
random_page_cost|planner|max|1.1|Lower for SSD storage (4 for HDD, 1.1 for SSD)|WARN
effective_io_concurrency|planner|min|200|Higher for SSD/NVMe (1 for HDD, 200+ for SSD)|WARN
seq_page_cost|planner|exact|1.0|Keep at 1.0, adjust random_page_cost instead|INFO
jit|planner|bool|on|Enable JIT for complex queries|INFO
constraint_exclusion|planner|exact|partition|Enable partition pruning|INFO
EOF
}

#------------------------------------------------------------------------------
# Security Rules
#------------------------------------------------------------------------------
pgtool_config_rules_security() {
    cat << 'EOF'
password_encryption|security|exact|scram-sha-256|Use SCRAM-SHA-256 authentication|CRITICAL
ssl|security|bool|on|Force SSL connections|CRITICAL
ssl_cert_file|security|regex|^/.*$|Use absolute path for SSL certificate|WARN
ssl_key_file|security|regex|^/.*$|Use absolute path for SSL key|WARN
shared_preload_libraries|security|regex|.*passwordcheck.*|Consider passwordcheck module|INFO
log_replication_commands|security|bool|on|Log replication commands|INFO
EOF
}

#------------------------------------------------------------------------------
# Get All Rules
#------------------------------------------------------------------------------
pgtool_config_rules_all() {
    pgtool_config_rules_memory
    pgtool_config_rules_connections
    pgtool_config_rules_wal
    pgtool_config_rules_vacuum
    pgtool_config_rules_replication
    pgtool_config_rules_logging
    pgtool_config_rules_planner
    pgtool_config_rules_security
}

#------------------------------------------------------------------------------
# Filter Rules by Category
#------------------------------------------------------------------------------
pgtool_config_rules_by_category() {
    local category="${1:-}"

    if [[ -z "$category" ]]; then
        pgtool_error "Category required"
        return $EXIT_INVALID_ARGS
    fi

    case "$category" in
        memory)
            pgtool_config_rules_memory
            ;;
        connections)
            pgtool_config_rules_connections
            ;;
        wal)
            pgtool_config_rules_wal
            ;;
        vacuum)
            pgtool_config_rules_vacuum
            ;;
        replication)
            pgtool_config_rules_replication
            ;;
        logging)
            pgtool_config_rules_logging
            ;;
        planner)
            pgtool_config_rules_planner
            ;;
        security)
            pgtool_config_rules_security
            ;;
        *)
            pgtool_error "Unknown category: $category"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

#------------------------------------------------------------------------------
# Parse Value with Units
# Supports: KB, MB, GB, TB, ms, s, min, h, d
#------------------------------------------------------------------------------
pgtool_config_parse_value() {
    local value="${1:-}"
    local target_unit="${2:-}"

    if [[ -z "$value" ]]; then
        return $EXIT_INVALID_ARGS
    fi

    # Remove whitespace and convert to lowercase
    value=$(echo "$value" | tr -d '[:space:]')

    # Handle pure numbers
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
        return 0
    fi

    # Handle bool-like values (case insensitive)
    local lvalue
    lvalue=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    case "$lvalue" in
        true|on|yes)
            echo "1"
            return 0
            ;;
        false|off|no)
            echo "0"
            return 0
            ;;
    esac

    # Extract number and unit using sed for portability
    local num unit
    num=$(echo "$value" | sed -E 's/^([0-9]+).*/\1/')
    unit=$(echo "$value" | sed -E 's/^[0-9]+//')

    if [[ -z "$num" || -z "$unit" ]]; then
        return $EXIT_INVALID_ARGS
    fi

    unit=$(echo "$unit" | tr '[:upper:]' '[:lower:]')

    # Convert to target unit if specified
    if [[ -n "$target_unit" ]]; then
        target_unit=$(echo "$target_unit" | tr '[:upper:]' '[:lower:]')

        case "$target_unit" in
            bytes|b)
                case "$unit" in
                    kb) echo $((num * 1024)) ;;
                    mb) echo $((num * 1024 * 1024)) ;;
                    gb) echo $((num * 1024 * 1024 * 1024)) ;;
                    tb) echo $((num * 1024 * 1024 * 1024 * 1024)) ;;
                    *) echo "$num" ;;
                esac
                ;;
            kb|k)
                case "$unit" in
                    b|bytes) echo $((num / 1024)) ;;
                    mb) echo $((num * 1024)) ;;
                    gb) echo $((num * 1024 * 1024)) ;;
                    tb) echo $((num * 1024 * 1024 * 1024)) ;;
                    *) echo "$num" ;;
                esac
                ;;
            mb|m)
                case "$unit" in
                    b|bytes) echo $((num / 1024 / 1024)) ;;
                    kb|k) echo $((num / 1024)) ;;
                    gb) echo $((num * 1024)) ;;
                    tb) echo $((num * 1024 * 1024)) ;;
                    *) echo "$num" ;;
                esac
                ;;
            gb|g)
                case "$unit" in
                    b|bytes) echo $((num / 1024 / 1024 / 1024)) ;;
                    kb|k) echo $((num / 1024 / 1024)) ;;
                    mb) echo $((num / 1024)) ;;
                    tb) echo $((num * 1024)) ;;
                    *) echo "$num" ;;
                esac
                ;;
            ms|milliseconds)
                case "$unit" in
                    s|sec|seconds) echo $((num * 1000)) ;;
                    min|m) echo $((num * 60 * 1000)) ;;
                    h|hr|hours) echo $((num * 60 * 60 * 1000)) ;;
                    d|days) echo $((num * 24 * 60 * 60 * 1000)) ;;
                    *) echo "$num" ;;
                esac
                ;;
            s|sec|seconds)
                case "$unit" in
                    ms) echo $((num / 1000)) ;;
                    min|m) echo $((num * 60)) ;;
                    h|hr|hours) echo $((num * 60 * 60)) ;;
                    d|days) echo $((num * 24 * 60 * 60)) ;;
                    *) echo "$num" ;;
                esac
                ;;
            *)
                echo "$num"
                ;;
        esac
    else
        echo "$num"
    fi
}

#------------------------------------------------------------------------------
# Format Bytes to Human Readable
#------------------------------------------------------------------------------
pgtool_config_format_bytes() {
    local bytes="${1:-}"
    local unit="${2:-auto}"

    if [[ -z "$bytes" || ! "$bytes" =~ ^[0-9]+$ ]]; then
        echo "$bytes"
        return 0
    fi

    # Auto-detect best unit
    if [[ "$unit" == "auto" ]]; then
        if [[ $bytes -ge $((1024 * 1024 * 1024 * 1024)) ]]; then
            unit="TB"
        elif [[ $bytes -ge $((1024 * 1024 * 1024)) ]]; then
            unit="GB"
        elif [[ $bytes -ge $((1024 * 1024)) ]]; then
            unit="MB"
        elif [[ $bytes -ge 1024 ]]; then
            unit="KB"
        else
            unit="B"
        fi
    fi

    # Convert to specified unit
    case "$unit" in
        TB|tb)
            printf "%.2f TB" "$(echo "scale=10; $bytes / 1024 / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0")"
            ;;
        GB|gb)
            printf "%.2f GB" "$(echo "scale=10; $bytes / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0")"
            ;;
        MB|mb)
            printf "%.2f MB" "$(echo "scale=10; $bytes / 1024 / 1024" | bc 2>/dev/null || echo "0")"
            ;;
        KB|kb)
            printf "%.2f KB" "$(echo "scale=10; $bytes / 1024" | bc 2>/dev/null || echo "0")"
            ;;
        B|b|bytes)
            printf "%d B" "$bytes"
            ;;
        *)
            echo "$bytes"
            ;;
    esac
}

#------------------------------------------------------------------------------
# Check if Value Meets Rule
#------------------------------------------------------------------------------
pgtool_config_check_rule() {
    local rule_name="${1:-}"
    local check_type="${2:-}"
    local threshold="${3:-}"
    local actual_value="${4:-}"

    if [[ -z "$rule_name" || -z "$check_type" || -z "$threshold" ]]; then
        echo "invalid"
        return $EXIT_INVALID_ARGS
    fi

    # Handle special threshold values
    local parsed_threshold
    local parsed_actual

    case "$check_type" in
        bool)
            # Boolean check: threshold is expected value (on/off, true/false)
            local expected="$threshold"
            local normalized_actual
            normalized_actual=$(echo "$actual_value" | tr '[:upper:]' '[:lower:]')
            local normalized_expected
            normalized_expected=$(echo "$expected" | tr '[:upper:]' '[:lower:]')

            # Normalize to 1/0
            local actual_bool expected_bool
            case "$normalized_actual" in
                true|on|yes|1) actual_bool=1 ;;
                false|off|no|0) actual_bool=0 ;;
                *) actual_bool="invalid" ;;
            esac

            case "$normalized_expected" in
                true|on|yes|1) expected_bool=1 ;;
                false|off|no|0) expected_bool=0 ;;
                try)
                    # Special: 'try' means prefer on but off is acceptable
                    if [[ "$actual_bool" == "1" ]]; then
                        echo "pass"
                    else
                        echo "warn"
                    fi
                    return 0
                    ;;
                *) expected_bool="invalid" ;;
            esac

            if [[ "$actual_bool" == "$expected_bool" ]]; then
                echo "pass"
            else
                echo "fail"
            fi
            ;;

        exact)
            # Exact match check
            if [[ "$actual_value" == "$threshold" ]]; then
                echo "pass"
            else
                echo "fail"
            fi
            ;;

        regex)
            # Regex match check
            if echo "$actual_value" | grep -qE "$threshold"; then
                echo "pass"
            else
                echo "fail"
            fi
            ;;

        range)
            # Range check - threshold can be:
            # - "X%" for percentage of some value
            # - "min-max" for numeric range
            # - single value for "around this value"
            if echo "$threshold" | grep -qE '^[0-9]+%$'; then
                # Percentage - requires external context (e.g., total RAM)
                # Return "unknown" - caller must provide context
                echo "unknown"
            elif echo "$threshold" | grep -qE '^[0-9]+-[0-9]+$'; then
                # min-max range
                local min_val max_val
                min_val=$(echo "$threshold" | sed -E 's/^([0-9]+)-[0-9]+$/\1/')
                max_val=$(echo "$threshold" | sed -E 's/^[0-9]+-([0-9]+)$/\1/')
                parsed_actual=$(pgtool_config_parse_value "$actual_value")

                if [[ -n "$parsed_actual" ]] && echo "$parsed_actual" | grep -qE '^[0-9]+$'; then
                    if [[ $parsed_actual -ge $min_val && $parsed_actual -le $max_val ]]; then
                        echo "pass"
                    else
                        echo "fail"
                    fi
                else
                    echo "unknown"
                fi
            else
                # Single value - check if "close enough"
                parsed_threshold=$(pgtool_config_parse_value "$threshold")
                parsed_actual=$(pgtool_config_parse_value "$actual_value")

                if [[ -n "$parsed_threshold" && -n "$parsed_actual" ]]; then
                    if [[ "$parsed_actual" == "$parsed_threshold" ]]; then
                        echo "pass"
                    else
                        echo "fail"
                    fi
                else
                    echo "unknown"
                fi
            fi
            ;;

        min)
            # Minimum value check
            parsed_threshold=$(pgtool_config_parse_value "$threshold")
            parsed_actual=$(pgtool_config_parse_value "$actual_value")

            if [[ -n "$parsed_threshold" && -n "$parsed_actual" ]]; then
                if echo "$parsed_actual" | grep -qE '^[0-9]+$' && echo "$parsed_threshold" | grep -qE '^[0-9]+$'; then
                    if [[ $parsed_actual -ge $parsed_threshold ]]; then
                        echo "pass"
                    else
                        echo "fail"
                    fi
                else
                    # String comparison for non-numeric
                    if [[ "$parsed_actual" == "$parsed_threshold" || "$parsed_actual" > "$parsed_threshold" ]]; then
                        echo "pass"
                    else
                        echo "fail"
                    fi
                fi
            else
                echo "unknown"
            fi
            ;;

        max)
            # Maximum value check
            parsed_threshold=$(pgtool_config_parse_value "$threshold")
            parsed_actual=$(pgtool_config_parse_value "$actual_value")

            if [[ -n "$parsed_threshold" && -n "$parsed_actual" ]]; then
                if echo "$parsed_actual" | grep -qE '^[0-9]+$' && echo "$parsed_threshold" | grep -qE '^[0-9]+$'; then
                    if [[ $parsed_actual -le $parsed_threshold ]]; then
                        echo "pass"
                    else
                        echo "fail"
                    fi
                else
                    # String comparison for non-numeric (reverse logic for max)
                    if [[ "$parsed_actual" == "$parsed_threshold" || "$parsed_actual" < "$parsed_threshold" ]]; then
                        echo "pass"
                    else
                        echo "fail"
                    fi
                fi
            else
                echo "unknown"
            fi
            ;;

        *)
            echo "invalid"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

#------------------------------------------------------------------------------
# Get Rule Details
#------------------------------------------------------------------------------
pgtool_config_get_rule() {
    local rule_name="${1:-}"

    if [[ -z "$rule_name" ]]; then
        return $EXIT_INVALID_ARGS
    fi

    pgtool_config_rules_all | while IFS='|' read -r name category check_type threshold recommendation severity; do
        if [[ "$name" == "$rule_name" ]]; then
            echo "name:$name"
            echo "category:$category"
            echo "check_type:$check_type"
            echo "threshold:$threshold"
            echo "recommendation:$recommendation"
            echo "severity:$severity"
            return 0
        fi
    done
}

#------------------------------------------------------------------------------
# List All Rule Names
#------------------------------------------------------------------------------
pgtool_config_list_rules() {
    local category="${1:-}"

    if [[ -n "$category" ]]; then
        pgtool_config_rules_by_category "$category" | cut -d'|' -f1
    else
        pgtool_config_rules_all | cut -d'|' -f1
    fi
}
