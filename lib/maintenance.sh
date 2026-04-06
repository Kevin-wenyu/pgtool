#!/bin/bash
# lib/maintenance.sh - Maintenance command group utilities

# Check dependencies
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

# Get list of tables needing vacuum
pgtool_maintenance_tables_needing_vacuum() {
    local threshold="${1:-10}"
    psql "${PGTOOL_CONN_OPTS[@]}" -t -c "
        SELECT schemaname || '.' || relname
        FROM pg_stat_user_tables
        WHERE n_dead_tup > $threshold * 1000
        ORDER BY n_dead_tup DESC
    " 2>/dev/null
}

# Get list of bloated indexes
pgtool_maintenance_bloated_indexes() {
    psql "${PGTOOL_CONN_OPTS[@]}" -t -c "
        SELECT schemaname || '.' || indexrelname
        FROM pg_stat_user_indexes i
        JOIN pg_index pi ON i.indexrelname = pi.indexrelname
        WHERE pg_relation_size(indexrelid) > pg_relation_size(relid) * 0.3
        AND pi.indisvalid
    " 2>/dev/null
}

# Check if table exists
pgtool_maintenance_table_exists() {
    local table_name="$1"
    local result
    result=$(psql "${PGTOOL_CONN_OPTS[@]}" -t -c "
        SELECT 1 FROM pg_tables
        WHERE schemaname || '.' || tablename = '$table_name'
        OR tablename = '$table_name'
        LIMIT 1
    " 2>/dev/null)
    [[ "$result" == " 1" ]]
}
