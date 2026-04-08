# Changelog

## [0.3.0] - 2026-04-08

### 新功能
- 为 admin 命令添加权限检查（需要超级用户权限）
- 添加 `--dry-run` 试运行选项到 kill-blocking, checkpoint, rotate-log 命令
- 添加审计日志支持 (pgtool_audit_admin)
- 添加 PostgreSQL 版本检测函数 (pgtool_pg_version_num)
- 添加角色检查函数 (pgtool_pg_is_superuser, pgtool_pg_is_replication_role)

### 修复
- 更新 hooks 配置到新版 Claude Code 格式

### 统计
- 6 个新功能提交
- admin 命令组增强安全性和可用性

## [0.2.0] - 2026-04-07

### 新增命令（10个）
- **check**: constraints, sequences, orphans, ssl
- **stat**: sequences, functions
- **admin**: rotate-log
- **analyze**: index-usage
- **monitor**: top
- **config**: validate

### 统计
- 总计 29 个命令（原 19 个 + 新增 10 个）
- 66 个测试全部通过

## [0.1.0] - 2026-04-01

### 初始版本

#### 命令（19个）
- **check**: xid, replication, autovacuum, connection
- **stat**: activity, locks, database, table, indexes
- **admin**: kill-blocking, cancel-query, checkpoint, reload
- **analyze**: bloat, missing-indexes, slow-queries, vacuum-stats
- **plugin**: list, example

#### 特性
- kubectl 风格的命令结构
- 模块化的插件系统
- 配置文件支持
- 环境变量支持
- 多种输出格式（table/json/csv/tsv）
- 完整的测试框架

#### 架构
- 8 个核心库模块
- 5 个命令组
- 17 个 SQL 文件
- 示例插件
