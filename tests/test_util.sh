#!/bin/bash
# tests/test_util.sh - 测试 util.sh 中的函数

# 加载测试框架
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

#==============================================================================
# 字符串测试
#==============================================================================

test_trim() {
    local result

    result=$(trim "  hello  ")
    assert_equals "hello" "$result"

    result=$(trim "hello")
    assert_equals "hello" "$result"

    result=$(trim "")
    assert_equals "" "$result"
}

test_to_lower() {
    local result

    result=$(to_lower "HELLO")
    assert_equals "hello" "$result"

    result=$(to_lower "Hello World")
    assert_equals "hello world" "$result"
}

test_to_upper() {
    local result

    result=$(to_upper "hello")
    assert_equals "HELLO" "$result"

    result=$(to_upper "Hello World")
    assert_equals "HELLO WORLD" "$result"
}

test_contains() {
    contains "hello world" "world" && assert_true "0" || assert_true "1"
    contains "hello world" "foo" && assert_true "1" || assert_true "0"
}

#==============================================================================
# 数值测试
#==============================================================================

test_is_int() {
    is_int "123" && assert_true "0" || assert_true "1"
    is_int "-123" && assert_true "0" || assert_true "1"
    is_int "abc" && assert_true "1" || assert_true "0"
    is_int "12.34" && assert_true "1" || assert_true "0"
}

test_num_compare() {
    num_compare "==" 5 5 && assert_true "0" || assert_true "1"
    num_compare "<" 3 5 && assert_true "0" || assert_true "1"
    num_compare ">" 5 3 && assert_true "0" || assert_true "1"
    num_compare "==" 3 5 && assert_true "1" || assert_true "0"
}

#==============================================================================
# 数组测试
#==============================================================================

test_array_contains() {
    local arr=("a" "b" "c")

    array_contains "b" "${arr[@]}" && assert_true "0" || assert_true "1"
    array_contains "d" "${arr[@]}" && assert_true "1" || assert_true "0"
}

test_array_length() {
    local arr=("a" "b" "c")
    local len

    len=$(array_length "${arr[@]}")
    assert_equals "3" "$len"
}

test_array_join() {
    local arr=("a" "b" "c")
    local result

    result=$(array_join "," "${arr[@]}")
    assert_equals "a,b,c" "$result"
}

#==============================================================================
# 文件测试
#==============================================================================

test_is_readable() {
    is_readable "$PGTOOL_ROOT/pgtool.sh" && assert_true "0" || assert_true "1"
    is_readable "/nonexistent/file" && assert_true "1" || assert_true "0"
}

#==============================================================================
# 注册测试
#==============================================================================

echo ""
echo "util.sh 测试:"

run_test "test_trim" "test_trim"
run_test "test_to_lower" "test_to_lower"
run_test "test_to_upper" "test_to_upper"
run_test "test_contains" "test_contains"
run_test "test_is_int" "test_is_int"
run_test "test_num_compare" "test_num_compare"
run_test "test_array_contains" "test_array_contains"
run_test "test_array_length" "test_array_length"
run_test "test_array_join" "test_array_join"
run_test "test_is_readable" "test_is_readable"
