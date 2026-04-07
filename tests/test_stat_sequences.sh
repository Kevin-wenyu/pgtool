#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"
test_sql_exists() { assert_true "[[ -f $PGTOOL_ROOT/sql/stat/sequences.sql ]]"; }
test_cmd_exists() { assert_true "[[ -f $PGTOOL_ROOT/commands/stat/sequences.sh ]]"; }
test_registered() {
    source "$PGTOOL_ROOT/commands/stat/index.sh"
    assert_contains "$PGTOOL_STAT_COMMANDS" "sequences"
}
echo ""
echo "Stat Sequences Tests:"
run_test "test_sql_exists" "SQL file exists"
run_test "test_cmd_exists" "Command script exists"
run_test "test_registered" "Command registered"
