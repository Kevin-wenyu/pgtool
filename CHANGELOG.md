# Changelog

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
