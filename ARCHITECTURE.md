# pgtool - PostgreSQL CLI Toolkit Architecture

## Overview

pgtool 是一个类似 kubectl 的 PostgreSQL 命令行工具，采用模块化、插件化架构设计。

---

## 1. 项目目录布局

```
pgtool/
├── pgtool.sh                  # CLI 主入口脚本
├── lib/                       # 核心库模块
│   ├── core.sh               # 核心函数（初始化、常量）
│   ├── cli.sh                # 命令行解析与分发
│   ├── log.sh                # 日志系统
│   ├── pg.sh                 # PostgreSQL 连接封装
│   ├── output.sh             # 输出格式化（table/json/csv）
│   ├── util.sh               # 通用工具函数
│   └── plugin.sh             # 插件管理器
├── commands/                  # 内置命令插件
│   ├── check/                # 检查类命令
│   │   ├── xid.sh
│   │   ├── replication.sh
│   │   ├── autovacuum.sh
│   │   └── index.sh          # 命令注册入口
│   ├── stat/                 # 统计类命令
│   │   ├── activity.sh
│   │   ├── locks.sh
│   │   ├── database.sh
│   │   └── index.sh
│   ├── admin/                # 管理类命令
│   │   ├── kill_blocking.sh
│   │   ├── cancel_query.sh
│   │   └── index.sh
│   └── analyze/              # 分析类命令
│       ├── bloat.sh
│       ├── missing_indexes.sh
│       └── index.sh
├── sql/                       # SQL 模块目录
│   ├── check/
│   │   ├── xid.sql
│   │   ├── replication.sql
│   │   └── autovacuum.sql
│   ├── stat/
│   │   ├── activity.sql
│   │   └── locks.sql
│   ├── admin/
│   │   └── kill_blocking.sql
│   └── analyze/
│       └── bloat.sql
├── conf/
│   └── pgtool.conf           # 配置文件模板
├── plugins/                   # 外部插件目录
│   └── README.md
├── docs/
│   ├── USAGE.md
│   └── DEVELOPMENT.md
└── tests/                     # 测试目录
    └── test_runner.sh
```

---

## 2. 模块职责

### 2.1 pgtool.sh（主入口）
- 脚本路径解析与自举
- 加载核心库模块
- 解析全局选项（-h, -v, --config）
- 调用命令分发器

### 2.2 lib/core.sh
- 定义常量（版本号、退出码、默认超时）
- 初始化运行时环境
- 路径计算与验证

### 2.3 lib/cli.sh
- 解析命令行参数
- 命令分发逻辑（group + command）
- 帮助信息生成
- 子命令自动发现

### 2.4 lib/log.sh
- 分级日志（DEBUG, INFO, WARN, ERROR, FATAL）
- 颜色输出控制
- 日志级别过滤
- 结构化日志格式

### 2.5 lib/pg.sh
- 数据库连接管理
- SQL 执行封装（带超时）
- 连接参数解析（PGHOST, PGPORT, PGUSER 等）
- 错误处理与重试

### 2.6 lib/output.sh
- 多格式输出（table, json, csv, tsv）
- 列宽自动计算
- 颜色主题
- 分页支持

### 2.7 lib/util.sh
- 字符串处理
- 数值比较
- 时间格式化
- 文件操作

### 2.8 lib/plugin.sh
- 插件目录扫描
- 动态加载
- 插件注册
- 依赖检查

---

## 3. 命令分发架构

### 3.1 命令结构

```
pgtool <group> <command> [options] [arguments]
```

示例：
```
pgtool check xid
pgtool stat activity --format=json
pgtool admin kill-blocking --pid=12345
```

### 3.2 分发流程

```
┌─────────────────┐
│   pgtool.sh     │
│  (主入口)        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   解析全局选项    │
│  -v, -h, --config│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   识别命令组      │
│  check/stat/...  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│  加载命令组索引   │────▶│ 未找到 → 错误    │
│  commands/<g>/   │     └─────────────────┘
│    index.sh     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│   分发到子命令    │────▶│ 未找到 → 帮助    │
│  <command>.sh    │     └─────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   执行命令逻辑    │
│  加载SQL → 执行  │
└─────────────────┘
```

### 3.3 命令注册机制

每个命令组通过 `index.sh` 注册可用命令：

```bash
# commands/check/index.sh
PGTOOL_CHECK_COMMANDS="xid:检查XID年龄,replication:检查复制状态,autovacuum:检查autovacuum状态"

pgtool_check_help() {
    echo "检查类命令："
    echo "  xid          检查事务ID年龄"
    echo "  replication  检查流复制状态"
    echo "  autovacuum   检查autovacuum状态"
}
```

---

## 4. 插件加载机制

### 4.1 内置命令（Internal Plugins）

内置命令位于 `commands/` 目录，随主程序一起分发。

### 4.2 外部插件（External Plugins）

外部插件位于 `plugins/` 目录，用户可自由扩展：

```
plugins/
├── mycompany/
│   ├── plugin.conf      # 插件配置
│   └── commands/        # 命令实现
│       └── custom_check.sh
└── another_plugin/
    └── ...
```

### 4.3 插件加载流程

```bash
# lib/plugin.sh

pgtool_load_plugins() {
    local plugin_dir="$PGTOOL_ROOT/plugins"

    for plugin in "$plugin_dir"/*/; do
        if [[ -f "$plugin/plugin.conf" ]]; then
            source "$plugin/plugin.conf"

            # 检查依赖
            if pgtool_check_plugin_deps "$PLUGIN_DEPENDS"; then
                # 加载插件命令
                for cmd in "$plugin/commands/"*.sh; do
                    source "$cmd"
                done
            fi
        fi
    done
}
```

### 4.4 插件配置格式

```bash
# plugin.conf
PLUGIN_NAME="mycompany"
PLUGIN_VERSION="1.0.0"
PLUGIN_DESCRIPTION="My Company Custom Checks"
PLUGIN_DEPENDS="pgtool>=1.0"
PLUGIN_COMMANDS="custom:自定义检查"
```

---

## 5. SQL 模块组织

### 5.1 SQL 文件命名规范

```
sql/<group>/<command>.sql
```

例如：
- `sql/check/xid.sql`
- `sql/stat/activity.sql`
- `sql/admin/kill_blocking.sql`

### 5.2 SQL 文件结构

每个 SQL 文件是一个独立的查询单元：

```sql
-- sql/check/xid.sql
-- 检查数据库 XID 年龄
-- 参数：无
-- 输出：datname, age, warning_level

SELECT
    datname,
    age(datfrozenxid) as age,
    CASE
        WHEN age(datfrozenxid) > 2000000000 THEN 'CRITICAL'
        WHEN age(datfrozenxid) > 1500000000 THEN 'WARNING'
        ELSE 'OK'
    END as warning_level
FROM pg_database
WHERE datallowconn
ORDER BY age DESC;
```

### 5.3 SQL 加载与执行

```bash
# 在命令脚本中
pgtool_exec_sql_file() {
    local group="$1"
    local command="$2"
    local sql_file="$PGTOOL_ROOT/sql/$group/$command.sql"

    if [[ ! -f "$sql_file" ]]; then
        pgtool_fatal "SQL文件不存在: $sql_file"
    fi

    # 使用 psql 执行，带超时控制
    timeout "$PGTOOL_TIMEOUT" psql \
        -v ON_ERROR_STOP=1 \
        -f "$sql_file" \
        "${PGTOOL_CONN_OPTS[@]}"
}
```

### 5.4 SQL 参数传递

使用 psql 变量机制：

```bash
psql -v threshold=1500000000 -f query.sql
```

```sql
-- query.sql
SELECT * FROM table WHERE age > :threshold;
```

---

## 6. 日志和错误处理策略

### 6.1 日志级别

| 级别   | 用途              | 默认显示 |
|--------|------------------|---------|
| DEBUG  | 调试信息          | 否      |
| INFO   | 一般信息          | 是      |
| WARN   | 警告              | 是      |
| ERROR  | 错误（可恢复）     | 是      |
| FATAL  | 致命错误（退出）   | 是      |

### 6.2 退出码定义

```bash
# lib/core.sh
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_ARGS=2
readonly EXIT_CONNECTION_ERROR=3
readonly EXIT_TIMEOUT=4
readonly EXIT_SQL_ERROR=5
readonly EXIT_NOT_FOUND=6
readonly EXIT_PERMISSION=7
```

### 6.3 错误处理模式

```bash
# 严格模式
set -o errexit
set -o nounset
set -o pipefail

# 错误处理函数
pgtool_fatal() {
    echo "[FATAL] $*" >&2
    exit "$EXIT_GENERAL_ERROR"
}

pgtool_error() {
    echo "[ERROR] $*" >&2
    return 1
}

pgtool_warn() {
    echo "[WARN] $*" >&2
}

pgtool_info() {
    echo "[INFO] $*"
}
```

### 6.4 SQL 错误处理

```bash
pgtool_exec_sql() {
    local sql="$1"
    local result

    if ! result=$(psql -v ON_ERROR_STOP=1 ... 2>&1); then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"
}
```

---

## 7. 配置管理

### 7.1 配置文件搜索路径

按优先级（高到低）：
1. `--config <file>` 显式指定
2. `$PGTOOL_CONFIG` 环境变量
3. `./.pgtool.conf`（当前目录）
4. `$HOME/.config/pgtool/pgtool.conf`
5. `/etc/pgtool/pgtool.conf`
6. 内置默认值

### 7.2 配置文件格式

```bash
# pgtool.conf

# 连接配置
PGHOST=localhost
PGPORT=5432
PGUSER=postgres
# PGPASSWORD 建议使用 .pgpass 文件

# 行为配置
PGTOOL_TIMEOUT=30
PGTOOL_FORMAT=table
PGTOOL_COLOR=auto
PGTOOL_LOG_LEVEL=INFO

# 自定义阈值
PGTOOL_XID_WARNING=1500000000
PGTOOL_XID_CRITICAL=2000000000

# 插件配置
PGTOOL_PLUGINS_DIR="$HOME/.pgtool/plugins"
```

### 7.3 配置加载流程

```bash
pgtool_load_config() {
    local config_file="${1:-}"

    # 1. 加载内置默认
    pgtool_set_defaults

    # 2. 按优先级搜索并加载
    for file in "$config_file" "${PGTOOL_CONFIG:-}" \
                "./.pgtool.conf" \
                "$HOME/.config/pgtool/pgtool.conf" \
                "/etc/pgtool/pgtool.conf"; do
        if [[ -n "$file" && -f "$file" ]]; then
            source "$file"
            PGTOOL_CONFIG_FILE="$file"
            break
        fi
    done
}
```

---

## 8. 输出格式化系统

### 8.1 支持的输出格式

- `table`：ASCII 表格（默认）
- `json`：JSON 格式
- `csv`：逗号分隔
- `tsv`：制表符分隔
- `simple`：简单文本

### 8.2 格式接口

```bash
# lib/output.sh

pgtool_output() {
    local format="${PGTOOL_FORMAT:-table}"
    local data="$1"

    case "$format" in
        table)
            pgtool_format_table "$data"
            ;;
        json)
            pgtool_format_json "$data"
            ;;
        csv)
            pgtool_format_csv "$data"
            ;;
        *)
            pgtool_error "未知格式: $format"
            return 1
            ;;
    esac
}
```

### 8.3 psql 格式集成

利用 psql 的 `--pset` 选项：

```bash
# table 格式
psql --pset format=aligned --pset border=2

# csv 格式
psql --pset format=csv

# 无格式
psql --pset tuples_only=on --pset format=unaligned
```

### 8.4 颜色控制

```bash
# lib/output.sh

pgtool_colorize() {
    local level="$1"
    local text="$2"

    if [[ "$PGTOOL_COLOR" == "never" ]] || \
       [[ "$PGTOOL_COLOR" == "auto" && ! -t 1 ]]; then
        echo "$text"
        return
    fi

    case "$level" in
        OK)      echo -e "\e[32m${text}\e[0m" ;;  # 绿色
        WARNING) echo -e "\e[33m${text}\e[0m" ;;  # 黄色
        CRITICAL) echo -e "\e[31m${text}\e[0m" ;; # 红色
        *)       echo "$text" ;;
    esac
}
```

---

## 9. 添加新命令的指南

### 9.1 创建新命令的步骤

#### 步骤 1：创建 SQL 文件

```bash
# sql/check/mycommand.sql
-- 描述：检查某指标
-- 作者：姓名
-- 日期：2024-XX-XX

SELECT ...;
```

#### 步骤 2：创建命令脚本

```bash
# commands/check/mycommand.sh

pgtool_check_mycommand() {
    local args=("$@")

    # 解析选项
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                pgtool_check_mycommand_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # 执行 SQL
    local result
    if ! result=$(pgtool_exec_sql_file "check" "mycommand"); then
        return $EXIT_SQL_ERROR
    fi

    # 格式化输出
    pgtool_output "$result"
}

pgtool_check_mycommand_help() {
    cat <<EOF
检查某指标

Usage: pgtool check mycommand [options]

Options:
  -h, --help    显示帮助

Examples:
  pgtool check mycommand
EOF
}
```

#### 步骤 3：注册命令

```bash
# commands/check/index.sh
# 在 PGTOOL_CHECK_COMMANDS 中添加
PGTOOL_CHECK_COMMANDS="...,mycommand:检查某指标"
```

### 9.2 命令模板

```bash
#!/bin/bash
# commands/<group>/<command>.sh
# 描述：简短描述
# 作者：姓名
# 日期：YYYY-MM-DD

set -euo pipefail

# 命令主函数
pgtool_<group>_<command>() {
    local opts=()
    local args=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_<group>_<command>_help
                return 0
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # 参数验证
    if [[ ${#args[@]} -eq 0 ]]; then
        pgtool_error "缺少必要参数"
        pgtool_<group>_<command>_help
        return $EXIT_INVALID_ARGS
    fi

    # 执行逻辑
    pgtool_exec_sql_file "<group>" "<command>" | pgtool_output
}

# 帮助函数
pgtool_<group>_<command>_help() {
    cat <<EOF
描述：简短描述

Usage: pgtool <group> <command> [options] [args]

Options:
  -h, --help    显示帮助

Examples:
  pgtool <group> <command>
EOF
}
```

---

## 10. 命令执行流程示例（pgtool check xid）

### 10.1 完整执行流程

```
用户输入：pgtool check xid

┌─────────────────────────────────────────────────────────────┐
│ 1. pgtool.sh 入口                                          │
│    - 设置 PGTOOL_ROOT                                       │
│    - source lib/core.sh（常量定义）                          │
│    - source lib/log.sh                                      │
│    - source lib/util.sh                                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. 解析全局选项                                             │
│    - pgtool -v check xid → 显示版本并退出                   │
│    - pgtool -h → 显示帮助                                   │
│    - pgtool --config /path/to/conf check xid               │
│    - 解析后剩余：check xid                                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. 加载配置                                                 │
│    - pgtool_load_config "$config_file"                      │
│    - 搜索路径：显式 → 环境变量 → ~/.config/pgtool/...       │
│    - 设置 PGTOOL_FORMAT, PGTOOL_TIMEOUT 等                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. 加载 CLI 模块                                            │
│    - source lib/cli.sh                                      │
│    - source lib/pg.sh（数据库连接）                          │
│    - source lib/output.sh                                   │
│    - source lib/plugin.sh                                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. 识别命令组                                               │
│    - group="check"                                          │
│    - command="xid"                                          │
│    - 检查 commands/check/ 目录是否存在                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. 加载命令组模块                                           │
│    - source commands/check/index.sh（命令注册表）            │
│    - 验证 "xid" 在 PGTOOL_CHECK_COMMANDS 中                  │
│    - source commands/check/xid.sh                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. 执行命令函数                                             │
│    - pgtool_check_xid "$@"                                  │
│    - 命令内部：                                              │
│      a) 解析子命令选项（--format, --threshold 等）           │
│      b) 检查数据库连接（pgtool_pg_test_connection）          │
│      c) 加载 SQL 文件：sql/check/xid.sql                     │
│      d) 执行 SQL（带超时控制）                               │
│      e) 处理结果（检查阈值，标记警告级别）                    │
│      f) 格式化输出（根据 PGTOOL_FORMAT）                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. 清理与退出                                               │
│    - 返回退出码（0=成功，1=有警告，2=有严重问题）             │
│    - 清理临时文件                                            │
└─────────────────────────────────────────────────────────────┘
```

### 10.2 代码流程示例

```bash
# pgtool check xid 的执行过程

# 1. 主入口
cd /path/to/pgtool
./pgtool.sh check xid

# 2. pgtool.sh 内容
#!/bin/bash
set -euo pipefail

# 计算根目录
PGTOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载核心
source "$PGTOOL_ROOT/lib/core.sh"
source "$PGTOOL_ROOT/lib/log.sh"
source "$PGTOOL_ROOT/lib/util.sh"

# 解析全局选项
shift  # 移除 "pgtool"

# 加载配置
pgtool_load_config

# 加载 CLI
source "$PGTOOL_ROOT/lib/cli.sh"
source "$PGTOOL_ROOT/lib/pg.sh"
source "$PGTOOL_ROOT/lib/output.sh"

# 分发命令
pgtool_dispatch "$@"

# 3. cli.sh 中的分发函数
pgtool_dispatch() {
    local group="$1"
    shift
    local cmd="$1"
    shift

    # 加载命令组
    source "$PGTOOL_ROOT/commands/$group/index.sh"

    # 验证并执行
    if pgtool_command_exists "$group" "$cmd"; then
        source "$PGTOOL_ROOT/commands/$group/$cmd.sh"
        "pgtool_${group}_${cmd}" "$@"
    else
        pgtool_fatal "未知命令: $group $cmd"
    fi
}

# 4. xid.sh 命令实现
pgtool_check_xid() {
    # 执行 SQL
    local output
    output=$(pgtool_exec_sql_file "check" "xid")

    # 检查阈值并标记颜色
    echo "$output" | while read -r line; do
        if [[ "$line" == *"CRITICAL"* ]]; then
            pgtool_colorize "CRITICAL" "$line"
            exit_code=2
        elif [[ "$line" == *"WARNING"* ]]; then
            pgtool_colorize "WARNING" "$line"
            exit_code=1
        else
            pgtool_colorize "OK" "$line"
        fi
    done

    return ${exit_code:-0}
}
```

---

## 11. 扩展建议

### 11.1 建议的命令集

```
check（健康检查）
  ├── xid          # 事务ID年龄
  ├── replication  # 流复制状态
  ├── autovacuum   # autovacuum状态
  ├── connection   # 连接数检查
  ├── storage      # 存储空间检查
  └── config       # 配置参数检查

stat（统计信息）
  ├── activity     # 活动会话
  ├── locks        # 锁等待
  ├── database     # 数据库统计
  ├── table        # 表统计
  └── index        # 索引使用统计

admin（管理操作）
  ├── kill-blocking   # 终止阻塞会话
  ├── cancel-query    # 取消查询
  ├── checkpoint      # 触发checkpoint
  └── reload          # 重载配置

analyze（分析诊断）
  ├── bloat           # 表膨胀分析
  ├── missing-indexes # 缺失索引建议
  ├── slow-queries    # 慢查询分析
  └── vacuum-stats    # vacuum统计
```

### 11.2 未来增强

- **配置文件热加载**
- **命令自动补全**（bash/zsh completion）
- **并发执行**（并行检查多个指标）
- **Webhook 集成**（检查结果通知）
- **历史数据存储**（趋势分析）

---

## 12. 总结

pgtool 架构特点：

1. **清晰的分层**：入口 → CLI → 命令 → SQL
2. **高可扩展性**：插件机制支持自定义命令
3. **配置灵活**：多级配置文件 + 环境变量
4. **安全可靠**：超时控制、错误处理、只读优先
5. **输出友好**：多格式支持、颜色标记

下一步：实现框架代码
