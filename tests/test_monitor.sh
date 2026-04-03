#!/bin/bash
# tests/test_monitor.sh - 测试 monitor 命令组

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

# 加载 CLI 模块以访问 PGTOOL_GROUPS
source "$PGTOOL_ROOT/lib/cli.sh"

# 加载 monitor 库
setup_monitor_tests() {
    if ! type pgtool_monitor_color_for_state &>/dev/null; then
        source "$PGTOOL_ROOT/lib/monitor.sh" 2>/dev/null || true
    fi
}

#==============================================================================
# 颜色函数测试
#==============================================================================

test_monitor_color_for_state() {
    setup_monitor_tests

    local color

    # active + 5s -> green
    color=$(pgtool_monitor_color_for_state "active" "5")
    assert_equals "$PGTOOL_MONITOR_COLOR_GREEN" "$color"

    # active + 30s -> yellow
    color=$(pgtool_monitor_color_for_state "active" "30")
    assert_equals "$PGTOOL_MONITOR_COLOR_YELLOW" "$color"

    # active + 120s -> red
    color=$(pgtool_monitor_color_for_state "active" "120")
    assert_equals "$PGTOOL_MONITOR_COLOR_RED" "$color"

    # idle -> green
    color=$(pgtool_monitor_color_for_state "idle")
    assert_equals "$PGTOOL_MONITOR_COLOR_GREEN" "$color"

    # critical state -> red
    color=$(pgtool_monitor_color_for_state "critical")
    assert_equals "$PGTOOL_MONITOR_COLOR_RED" "$color"

    # warning state -> yellow
    color=$(pgtool_monitor_color_for_state "warning")
    assert_equals "$PGTOOL_MONITOR_COLOR_YELLOW" "$color"
}

test_monitor_color_for_lag() {
    setup_monitor_tests

    local color

    # 10MB -> green (10485760 bytes)
    color=$(pgtool_monitor_color_for_lag "10485760")
    assert_equals "$PGTOOL_MONITOR_COLOR_GREEN" "$color"

    # 200MB -> yellow (209715200 bytes)
    color=$(pgtool_monitor_color_for_lag "209715200")
    assert_equals "$PGTOOL_MONITOR_COLOR_YELLOW" "$color"

    # 2GB -> red (2147483648 bytes)
    color=$(pgtool_monitor_color_for_lag "2147483648")
    assert_equals "$PGTOOL_MONITOR_COLOR_RED" "$color"
}

#==============================================================================
# 文件存在性测试
#==============================================================================

test_monitor_commands_exist() {
    local files=(
        "$PGTOOL_ROOT/commands/monitor/index.sh"
        "$PGTOOL_ROOT/commands/monitor/queries.sh"
        "$PGTOOL_ROOT/commands/monitor/connections.sh"
        "$PGTOOL_ROOT/commands/monitor/replication.sh"
    )

    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "文件不存在: $file" >&2
            return 1
        fi
    done
}

test_monitor_sql_files_exist() {
    local files=(
        "$PGTOOL_ROOT/sql/monitor/queries.sql"
        "$PGTOOL_ROOT/sql/monitor/connections.sql"
        "$PGTOOL_ROOT/sql/monitor/replication.sql"
    )

    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "文件不存在: $file" >&2
            return 1
        fi
    done
}

#==============================================================================
# CLI 注册测试
#==============================================================================

test_monitor_registered_in_cli() {
    local found=false
    local group

    for group in "${PGTOOL_GROUPS[@]}"; do
        if [[ "$group" == "monitor" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" != "true" ]]; then
        echo "monitor 未在 PGTOOL_GROUPS 中注册" >&2
        return 1
    fi
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "monitor 命令组测试:"

run_test "test_monitor_color_for_state" "test_monitor_color_for_state"
run_test "test_monitor_color_for_lag" "test_monitor_color_for_lag"
run_test "test_monitor_commands_exist" "test_monitor_commands_exist"
run_test "test_monitor_sql_files_exist" "test_monitor_sql_files_exist"
run_test "test_monitor_registered_in_cli" "test_monitor_registered_in_cli"
