#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

test_sql_exists() { assert_true "[[ -f $PGTOOL_ROOT/sql/check/orphans.sql ]]"; }
test_cmd_exists() { assert_true "[[ -f $PGTOOL_ROOT/commands/check/orphans.sh ]]"; }
test_registered() {
    source "$PGTOOL_ROOT/commands/check/index.sh"
    assert_contains "$PGTOOL_CHECK_COMMANDS" "orphans"
}

echo ""
echo "Check Orphans Tests:"
run_test "test_sql_exists" "SQL file exists"
run_test "test_cmd_exists" "Command script exists"
run_test "test_registered" "Command registered"
