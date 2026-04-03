#!/bin/bash
# tests/test_backup.sh - Backup module tests

source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

setup_backup_tests() {
    if [[ -z "${PGTOOL_GROUPS:-}" ]]; then
        source "$PGTOOL_ROOT/lib/cli.sh" 2>/dev/null || true
    fi
    if ! type pgtool_backup_detect_tool &>/dev/null; then
        source "$PGTOOL_ROOT/lib/backup.sh" 2>/dev/null || true
    fi
}

test_backup_lib_loaded() {
    assert_true "$(type pgtool_backup_detect_tool &>/dev/null && echo 0 || echo 1)"
    assert_true "$(type pgtool_backup_pgbackrest_check &>/dev/null && echo 0 || echo 1)"
    assert_true "$(type pgtool_backup_barman_check &>/dev/null && echo 0 || echo 1)"
}

test_backup_commands_exist() {
    local cmds="index status verify archive list info"
    local missing=()
    for cmd in $cmds; do
        if [[ ! -f "$PGTOOL_ROOT/commands/backup/$cmd.sh" ]]; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "缺失命令: ${missing[*]}" >&2
        return 1
    fi
}

test_backup_sql_files_exist() {
    if [[ ! -f "$PGTOOL_ROOT/sql/backup/archive.sql" ]]; then
        echo "缺失 SQL: backup/archive" >&2
        return 1
    fi
}

test_backup_registered_in_cli() {
    local found=false
    for g in "${PGTOOL_GROUPS[@]}"; do
        [[ "$g" == "backup" ]] && found=true
    done
    if [[ "$found" != true ]]; then
        echo "backup 未注册" >&2
        return 1
    fi
}

test_backup_tool_detection() {
    assert_true "$(type pgtool_backup_detect_tool &>/dev/null && echo 0 || echo 1)"
}

setup_backup_tests
run_test "backup_lib_loaded" test_backup_lib_loaded
run_test "backup_commands_exist" test_backup_commands_exist
run_test "backup_sql_files_exist" test_backup_sql_files_exist
run_test "backup_registered" test_backup_registered_in_cli
run_test "backup_tool_detection" test_backup_tool_detection
