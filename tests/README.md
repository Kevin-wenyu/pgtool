# pgtool 测试文档

## 快速开始

```bash
# 运行所有测试
cd tests
./run.sh

# 运行特定测试
./run.sh test_util
./run.sh test_core
./run.sh test_cli
./run.sh test_commands
./run.sh test_pg
./run.sh test_plugin

# 查看帮助
./run.sh --help
```

## 测试结构

```
tests/
├── run.sh              # 测试入口
├── test_runner.sh      # 测试框架
├── test_util.sh        # 测试 util.sh
├── test_core.sh        # 测试 core.sh
├── test_cli.sh         # 测试 cli.sh
├── test_commands.sh    # 测试命令
├── test_pg.sh          # 测试 pg.sh
└── test_plugin.sh      # 测试 plugin.sh
```

## 编写测试

### 1. 创建测试文件

创建 `test_feature.sh`：

```bash
#!/bin/bash
# tests/test_feature.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

# 测试函数
my_test() {
    local result
    result=$(some_function)
    assert_equals "expected" "$result"
}

# 注册测试
echo ""
echo "Feature 测试:"
run_test "my_test" "my_test"
```

### 2. 可用断言

- `assert_equals expected actual` - 断言相等
- `assert_true value` - 断言为真
- `assert_false value` - 断言为假
- `assert_not_empty value` - 断言非空
- `assert_empty value` - 断言为空
- `assert_contains string substring` - 断言包含

### 3. 跳过测试

```bash
test_with_db() {
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        skip_test "需要数据库连接"
        return
    fi
    # 测试逻辑...
}
```

## 运行结果

```
========================================
              测试汇总
========================================
  通过: 25
  失败: 0
  跳过: 2
  总计: 27
  用时: 3s
========================================
所有测试通过!
```

## CI 集成

GitHub Actions 示例：

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: |
          cd tests
          ./run.sh
```
