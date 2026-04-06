#!/bin/bash
# tests/test_maintenance.sh - Maintenance command group tests

set -e

PGTOOL_ROOT="${PGTOOL_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}"
source "$PGTOOL_ROOT/tests/test_runner.sh"
source "$PGTOOL_ROOT/lib/maintenance.sh"

test_maintenance_lib_loaded() {
    assert_true "$(type pgtool_maintenance_tables_needing_vacuum &>/dev/null && echo 0 || echo 1)" "maintenance库应该加载"
}

test_maintenance_commands_exist() {
    local cmds=("vacuum" "reindex" "analyze")
    for cmd in "${cmds[@]}"; do
        assert_true "$(test -f "$PGTOOL_ROOT/commands/maintenance/${cmd}.sh" && echo 0 || echo 1)" "命令 ${cmd}.sh 应该存在"
    done
}

test_maintenance_index_exists() {
    assert_true "$(test -f "$PGTOOL_ROOT/commands/maintenance/index.sh" && echo 0 || echo 1)" "maintenance/index.sh 应该存在"
}

test_maintenance_sql_files_exist() {
    local sqls=("vacuum" "reindex" "analyze")
    for sql in "${sqls[@]}"; do
        assert_true "$(test -f "$PGTOOL_ROOT/sql/maintenance/${sql}.sql" && echo 0 || echo 1)" "SQL ${sql}.sql 应该存在"
    done
}

# Run tests
run_test "test_maintenance_lib_loaded" "test_maintenance_lib_loaded"
run_test "test_maintenance_commands_exist" "test_maintenance_commands_exist"
run_test "test_maintenance_index_exists" "test_maintenance_index_exists"
run_test "test_maintenance_sql_files_exist" "test_maintenance_sql_files_exist"

# 运行清理并输出汇总
teardown
