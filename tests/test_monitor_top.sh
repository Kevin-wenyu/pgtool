#!/bin/bash
# tests/test_monitor_top.sh - 测试 monitor top 命令

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

#==============================================================================
# 文件存在性测试
#==============================================================================

test_monitor_top_sql_exists() {
    if [[ -f "$PGTOOL_ROOT/sql/monitor/top.sql" ]]; then
        assert_true "0"
    else
        assert_true "1"
    fi
}

test_monitor_top_command_exists() {
    if [[ -f "$PGTOOL_ROOT/commands/monitor/top.sh" ]]; then
        assert_true "0"
    else
        assert_true "1"
    fi
}

test_monitor_top_command_is_executable() {
    if [[ -x "$PGTOOL_ROOT/commands/monitor/top.sh" ]]; then
        assert_true "0"
    else
        assert_true "1"
    fi
}

#==============================================================================
# SQL 内容测试
#==============================================================================

test_monitor_top_sql_contains_pid() {
    local content
    content=$(cat "$PGTOOL_ROOT/sql/monitor/top.sql" 2>/dev/null)
    assert_contains "$content" "pid"
}

test_monitor_top_sql_contains_usename() {
    local content
    content=$(cat "$PGTOOL_ROOT/sql/monitor/top.sql" 2>/dev/null)
    assert_contains "$content" "usename"
}

test_monitor_top_sql_contains_datname() {
    local content
    content=$(cat "$PGTOOL_ROOT/sql/monitor/top.sql" 2>/dev/null)
    assert_contains "$content" "datname"
}

test_monitor_top_sql_contains_state() {
    local content
    content=$(cat "$PGTOOL_ROOT/sql/monitor/top.sql" 2>/dev/null)
    assert_contains "$content" "state"
}

test_monitor_top_sql_contains_duration() {
    local content
    content=$(cat "$PGTOOL_ROOT/sql/monitor/top.sql" 2>/dev/null)
    assert_contains "$content" "duration"
}

test_monitor_top_sql_contains_query() {
    local content
    content=$(cat "$PGTOOL_ROOT/sql/monitor/top.sql" 2>/dev/null)
    assert_contains "$content" "query"
}

test_monitor_top_sql_contains_pg_stat_activity() {
    local content
    content=$(cat "$PGTOOL_ROOT/sql/monitor/top.sql" 2>/dev/null)
    assert_contains "$content" "pg_stat_activity"
}

#==============================================================================
# 命令内容测试
#==============================================================================

test_monitor_top_command_contains_main_function() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/top.sh" 2>/dev/null)
    assert_contains "$content" "pgtool_monitor_top()"
}

test_monitor_top_command_contains_help_function() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/top.sh" 2>/dev/null)
    assert_contains "$content" "pgtool_monitor_top_help()"
}

test_monitor_top_command_contains_once_mode() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/top.sh" 2>/dev/null)
    assert_contains "$content" "--once"
}

test_monitor_top_command_contains_interval_option() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/top.sh" 2>/dev/null)
    assert_contains "$content" "interval"
}

test_monitor_top_command_contains_limit_option() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/top.sh" 2>/dev/null)
    assert_contains "$content" "limit"
}

test_monitor_top_command_contains_quit_key() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/top.sh" 2>/dev/null)
    assert_contains "$content" "q"
}

test_monitor_top_command_contains_pause_key() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/top.sh" 2>/dev/null)
    assert_contains "$content" "p"
}

test_monitor_top_command_contains_paused_logic() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/top.sh" 2>/dev/null)
    assert_contains "$content" "paused"
}

#==============================================================================
# 索引注册测试
#==============================================================================

test_monitor_top_registered_in_index() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/index.sh" 2>/dev/null)
    assert_contains "$content" "top"
}

test_monitor_top_in_commands_list() {
    local content
    content=$(cat "$PGTOOL_ROOT/commands/monitor/index.sh" 2>/dev/null)
    assert_contains "$content" "PGTOOL_MONITOR_COMMANDS"
    assert_contains "$content" "top:"
}

#==============================================================================
# 帮助信息测试
#==============================================================================

test_monitor_help_contains_top() {
    local output
    output=$("$PGTOOL_ROOT/pgtool.sh" monitor --help 2>&1)
    assert_contains "$output" "top"
}

test_monitor_top_help_contains_usage() {
    local output
    output=$("$PGTOOL_ROOT/pgtool.sh" monitor top --help 2>&1)
    assert_contains "$output" "Usage"
}

test_monitor_top_help_contains_interval() {
    local output
    output=$("$PGTOOL_ROOT/pgtool.sh" monitor top --help 2>&1)
    assert_contains "$output" "interval"
}

test_monitor_top_help_contains_limit() {
    local output
    output=$("$PGTOOL_ROOT/pgtool.sh" monitor top --help 2>&1)
    assert_contains "$output" "limit"
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "Monitor Top 命令测试:"

run_test "test_monitor_top_sql_exists" "test_monitor_top_sql_exists"
run_test "test_monitor_top_command_exists" "test_monitor_top_command_exists"
run_test "test_monitor_top_command_is_executable" "test_monitor_top_command_is_executable"
run_test "test_monitor_top_sql_contains_pid" "test_monitor_top_sql_contains_pid"
run_test "test_monitor_top_sql_contains_usename" "test_monitor_top_sql_contains_usename"
run_test "test_monitor_top_sql_contains_datname" "test_monitor_top_sql_contains_datname"
run_test "test_monitor_top_sql_contains_state" "test_monitor_top_sql_contains_state"
run_test "test_monitor_top_sql_contains_duration" "test_monitor_top_sql_contains_duration"
run_test "test_monitor_top_sql_contains_query" "test_monitor_top_sql_contains_query"
run_test "test_monitor_top_sql_contains_pg_stat_activity" "test_monitor_top_sql_contains_pg_stat_activity"
run_test "test_monitor_top_command_contains_main_function" "test_monitor_top_command_contains_main_function"
run_test "test_monitor_top_command_contains_help_function" "test_monitor_top_command_contains_help_function"
run_test "test_monitor_top_command_contains_once_mode" "test_monitor_top_command_contains_once_mode"
run_test "test_monitor_top_command_contains_interval_option" "test_monitor_top_command_contains_interval_option"
run_test "test_monitor_top_command_contains_limit_option" "test_monitor_top_command_contains_limit_option"
run_test "test_monitor_top_command_contains_quit_key" "test_monitor_top_command_contains_quit_key"
run_test "test_monitor_top_command_contains_pause_key" "test_monitor_top_command_contains_pause_key"
run_test "test_monitor_top_command_contains_paused_logic" "test_monitor_top_command_contains_paused_logic"
run_test "test_monitor_top_registered_in_index" "test_monitor_top_registered_in_index"
run_test "test_monitor_top_in_commands_list" "test_monitor_top_in_commands_list"
run_test "test_monitor_help_contains_top" "test_monitor_help_contains_top"
run_test "test_monitor_top_help_contains_usage" "test_monitor_top_help_contains_usage"
run_test "test_monitor_top_help_contains_interval" "test_monitor_top_help_contains_interval"
run_test "test_monitor_top_help_contains_limit" "test_monitor_top_help_contains_limit"
