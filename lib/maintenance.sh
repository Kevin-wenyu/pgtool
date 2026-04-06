#!/bin/bash
# lib/maintenance.sh - Maintenance command group utilities

# Check dependencies
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

# Validate that a value is a positive integer
pgtool_maintenance_validate_int() {
    local value="$1"
    local name="$2"

    if [[ -z "$value" ]]; then
        pgtool_error "${name}: 值不能为空"
        return $EXIT_INVALID_ARGS
    fi

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        pgtool_error "${name}: 必须是正整数, 得到 '$value'"
        return $EXIT_INVALID_ARGS
    fi

    return $EXIT_SUCCESS
}

# Escape SQL identifier (table name, column name, etc.)
pgtool_maintenance_escape_identifier() {
    local ident="$1"
    # Replace double quotes with two double quotes (SQL standard escaping)
    echo "${ident//\"/\"\"}"
}

# Get list of tables needing vacuum
pgtool_maintenance_tables_needing_vacuum() {
    local threshold="${1:-10}"

    # Validate threshold parameter
    if ! pgtool_maintenance_validate_int "$threshold" "threshold"; then
        return $EXIT_INVALID_ARGS
    fi

    local output
    output=$(timeout "${PGTOOL_TIMEOUT}" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --tuples-only \
        --command="
            SELECT schemaname || '.' || relname
            FROM pg_stat_user_tables
            WHERE n_dead_tup > $threshold * 1000
            ORDER BY n_dead_tup DESC
        " \
        --quiet 2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "查询超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "查询失败: $output"
        return $EXIT_SQL_ERROR
    fi

    echo "$output"
}

# Get list of bloated indexes
pgtool_maintenance_bloated_indexes() {
    local output
    output=$(timeout "${PGTOOL_TIMEOUT}" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --tuples-only \
        --command="
            SELECT schemaname || '.' || indexrelname
            FROM pg_stat_user_indexes i
            JOIN pg_index pi ON i.indexrelname = pi.indexrelname
            WHERE pg_relation_size(indexrelid) > pg_relation_size(relid) * 0.3
            AND pi.indisvalid
        " \
        --quiet 2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "查询超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "查询失败: $output"
        return $EXIT_SQL_ERROR
    fi

    echo "$output"
}

# Check if table exists
pgtool_maintenance_table_exists() {
    local table_name="$1"

    if [[ -z "$table_name" ]]; then
        pgtool_error "table_name 不能为空"
        return $EXIT_INVALID_ARGS
    fi

    # Escape the table name for safe SQL usage
    local escaped_table_name
    escaped_table_name=$(pgtool_maintenance_escape_identifier "$table_name")

    local output
    output=$(timeout "${PGTOOL_TIMEOUT}" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --tuples-only \
        --command="
            SELECT 1 FROM pg_tables
            WHERE schemaname || '.' || tablename = '$escaped_table_name'
            OR tablename = '$escaped_table_name'
            LIMIT 1
        " \
        --quiet 2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "查询超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "查询失败: $output"
        return $EXIT_SQL_ERROR
    fi

    [[ "$output" == *"1"* ]]
}
