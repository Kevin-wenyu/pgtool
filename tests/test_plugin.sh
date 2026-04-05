#!/bin/bash
# tests/test_plugin.sh - 测试插件系统

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

# 加载插件模块
source "$PGTOOL_ROOT/lib/plugin.sh"

#==============================================================================
# 插件目录测试
#==============================================================================

test_plugins_dir_exists() {
    [[ -d "$PGTOOL_PLUGINS_DIR" ]] && assert_true "0" || assert_true "1"
}

test_example_plugin_exists() {
    [[ -d "$PGTOOL_PLUGINS_DIR/example" ]] && assert_true "0" || assert_true "1"
    [[ -f "$PGTOOL_PLUGINS_DIR/example/plugin.conf" ]] && assert_true "0" || assert_true "1"
}

test_example_plugin_config() {
    local config_file="$PGTOOL_PLUGINS_DIR/example/plugin.conf"

    source "$config_file"

    assert_equals "example" "$PLUGIN_NAME"
    assert_not_empty "$PLUGIN_VERSION"
    assert_not_empty "$PLUGIN_DESCRIPTION"
    assert_not_empty "$PLUGIN_COMMANDS"
}

test_example_plugin_commands() {
    local cmd_dir="$PGTOOL_PLUGINS_DIR/example/commands"

    [[ -f "$cmd_dir/hello.sh" ]] && assert_true "0" || assert_true "1"
    [[ -f "$cmd_dir/version.sh" ]] && assert_true "0" || assert_true "1"
}

#==============================================================================
# 版本比较测试
#==============================================================================

test_version_to_num() {
    local result

    result=$(pgtool_version_to_num "1.0.0")
    assert_equals "10000" "$result"

    result=$(pgtool_version_to_num "1.2.3")
    assert_equals "10203" "$result"

    result=$(pgtool_version_to_num "10.0.0")
    assert_equals "100000" "$result"
}

test_version_compare() {
    # 相等
    pgtool_version_compare "1.0.0" "=" "1.0.0" && assert_true "0" || assert_true "1"

    # 大于
    pgtool_version_compare "1.1.0" ">" "1.0.0" && assert_true "0" || assert_true "1"

    # 小于
    pgtool_version_compare "1.0.0" "<" "1.1.0" && assert_true "0" || assert_true "1"

    # 大于等于
    pgtool_version_compare "1.0.0" ">=" "1.0.0" && assert_true "0" || assert_true "1"
    pgtool_version_compare "1.1.0" ">=" "1.0.0" && assert_true "0" || assert_true "1"
}

#==============================================================================
# 插件命令注册测试
#==============================================================================

test_plugin_commands_registration() {
    # 示例插件应该注册了命令
    local var_name="PGTOOL_PLUGIN_example_COMMANDS"
    local commands
    commands=$(eval echo "\$$var_name" 2>/dev/null || echo "")

    assert_contains "$commands" "hello"
    assert_contains "$commands" "version"
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "plugin.sh 测试:"

run_test "test_plugins_dir_exists" "test_plugins_dir_exists"
run_test "test_example_plugin_exists" "test_example_plugin_exists"
run_test "test_example_plugin_config" "test_example_plugin_config"
run_test "test_example_plugin_commands" "test_example_plugin_commands"
run_test "test_version_to_num" "test_version_to_num"
run_test "test_version_compare" "test_version_compare"
run_test "test_plugin_commands_registration" "test_plugin_commands_registration"

# 运行清理并输出汇总
teardown
