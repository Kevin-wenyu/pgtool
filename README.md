# pgtool - PostgreSQL CLI Toolkit

类似 kubectl 的 PostgreSQL 运维命令行工具。

## 特性

- **kubectl 风格**：熟悉的命令行体验
- **模块化设计**：易于扩展的命令系统
- **插件支持**：可自定义扩展功能
- **19+ 命令**：覆盖日常运维场景
- **安全优先**：只读检查类命令默认安全

## 快速安装

```bash
# 方式1：直接安装
git clone <repo-url>
cd pgtool
./install.sh

# 方式2：安装到指定目录
./install.sh --prefix=$HOME/.local
```

## 快速开始

```bash
# 查看帮助
pgtool --help

# 检查数据库健康
pgtool check xid
pgtool check connection

# 查看统计信息
pgtool stat activity
pgtool stat locks
pgtool stat database

# 分析诊断
pgtool analyze bloat
pgtool analyze missing-indexes

# 管理操作（谨慎使用）
pgtool admin checkpoint --force
pgtool admin reload --force
```

## 命令清单

| 组 | 命令 | 说明 |
|---|---|---|
| **check** | xid | 检查 XID 年龄，预警回卷风险 |
| | replication | 检查流复制状态 |
| | autovacuum | 检查 autovacuum 状态 |
| | connection | 检查连接数使用 |
| **stat** | activity | 查看活动会话 |
| | locks | 查看锁等待 |
| | database | 数据库级统计 |
| | table | 表级统计 |
| | indexes | 索引使用情况 |
| **admin** | kill-blocking | 终止阻塞会话 |
| | cancel-query | 取消查询 |
| | checkpoint | 触发检查点 |
| | reload | 重载配置 |
| **analyze** | bloat | 分析表膨胀 |
| | missing-indexes | 查找缺失索引 |
| | slow-queries | 分析慢查询 |
| | vacuum-stats | vacuum 统计 |
| **plugin** | list | 列出插件 |

## 配置

配置文件搜索路径（按优先级）：
1. `./.pgtool.conf` - 当前目录
2. `~/.config/pgtool/pgtool.conf` - 用户配置
3. `~/.pgtool.conf` - 用户主目录
4. `/etc/pgtool/pgtool.conf` - 系统配置

## 开发

```bash
# 运行测试
cd tests && ./run.sh

# 创建插件
mkdir -p ~/.pgtool/plugins/myplugin/commands
cp -r plugins/example/* ~/.pgtool/plugins/myplugin/
# 修改 plugin.conf
```

## 文档

- [架构设计](ARCHITECTURE.md)
- [插件开发](docs/PLUGIN_DEVELOPMENT.md)
- [测试说明](tests/README.md)

## License

MIT
