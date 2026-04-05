#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

setup_config_tests() {
    if [[ -z "${PGTOOL_GROUPS:-}" ]]; then
        source "$PGTOOL_ROOT/lib/cli.sh" 2>/dev/null || true
    fi
    if ! type pgtool_config_detect_memory &>/dev/null; then
        source "$PGTOOL_ROOT/lib/config.sh" 2>/dev/null || true
        source "$PGTOOL_ROOT/lib/config_rules.sh" 2>/dev/null || true
    fi
}

test_config_lib_loaded() {
    assert_true "$(type pgtool_config_detect_memory &>/dev/null && echo 0 || echo 1)"
    assert_true "$(type pgtool_config_rules_all &>/dev/null && echo 0 || echo 1)"
}

test_config_commands_exist() {
    local cmds="index analyze diff get set reset export"
    for cmd in $cmds; do
        if [[ ! -f "$PGTOOL_ROOT/commands/config/$cmd.sh" ]]; then
            echo "缺失命令: $cmd" >&2
            return 1
        fi
    done
}

test_config_sql_files_exist() {
    for sql in analyze get; do
        if [[ ! -f "$PGTOOL_ROOT/sql/config/$sql.sql" ]]; then
            echo "缺失 SQL: $sql" >&2
            return 1
        fi
    done
}

test_config_registered_in_cli() {
    local found=false
    for g in "${PGTOOL_GROUPS[@]}"; do
        [[ "$g" == "config" ]] && found=true
    done
    [[ "$found" == true ]]
}

setup_config_tests
run_test "config_lib_loaded" test_config_lib_loaded
run_test "config_commands_exist" test_config_commands_exist
run_test "config_sql_files_exist" test_config_sql_files_exist
run_test "config_registered" test_config_registered_in_cli
