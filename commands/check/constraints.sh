#!/bin/bash
# commands/check/constraints.sh - Check for constraint violations

#==============================================================================
# Main Function
#==============================================================================

pgtool_check_constraints() {
    # Parse parameters
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_check_constraints_help
                return 0
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            -*)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "检查数据库约束状态..."
    echo ""

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "check" "constraints"); then
        pgtool_fatal "SQL文件未找到: check/constraints"
    fi

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Execute SQL
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # Display result
    echo "$result"

    return $EXIT_SUCCESS
}

#==============================================================================
# Help Function
#==============================================================================

pgtool_check_constraints_help() {
    cat <<EOF
检查数据库约束状态

检查外键约束、CHECK约束、唯一约束等的状态，帮助发现潜在的约束问题。

用法: pgtool check constraints [选项]

选项:
  -h, --help          显示帮助

示例:
  pgtool check constraints
EOF
}
