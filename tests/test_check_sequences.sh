#!/bin/bash
# tests/test_check_sequences.sh - Tests for check sequences command

source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

# Test: SQL file exists
test_sql_file_exists() {
    assert_true "$(test -f "$PGTOOL_ROOT/sql/check/sequences.sql" && echo 0 || echo 1)"
}

# Test: Command script exists and is executable
test_command_script_exists() {
    assert_true "$(test -f "$PGTOOL_ROOT/commands/check/sequences.sh" && echo 0 || echo 1)"
    assert_true "$(test -x "$PGTOOL_ROOT/commands/check/sequences.sh" && echo 0 || echo 1)"
}

# Test: Command is registered in index
test_command_registered() {
    source "$PGTOOL_ROOT/commands/check/index.sh"
    assert_contains "$PGTOOL_CHECK_COMMANDS" "sequences"
}

# Test: Help function works (dry run)
test_help_command() {
    local output
    output=$(cd "$PGTOOL_ROOT" && ./pgtool.sh check sequences --help 2>&1)
    assert_contains "$output" "检查序列"
}

# Test: SQL syntax is valid (if database available)
test_sql_syntax_valid() {
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        skip_test "需要数据库连接来验证SQL语法"
        return
    fi

    local result
    result=$(psql "${PGTOOL_CONN_OPTS[@]}" -v ON_ERROR_STOP=1 -f "$PGTOOL_ROOT/sql/check/sequences.sql" 2>&1)
    assert_equals "0" "$?"
}

# Run tests
echo ""
echo "Check Sequences Command Tests:"
run_test "SQL file exists" "test_sql_file_exists"
run_test "Command script exists and executable" "test_command_script_exists"
run_test "Command registered in index" "test_command_registered"
run_test "Help command works" "test_help_command"
run_test "SQL syntax valid" "test_sql_syntax_valid"
