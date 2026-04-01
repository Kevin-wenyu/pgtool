# pgtool 开发计划

## 项目目标
开发一个类似 kubectl 的 PostgreSQL CLI 工具，采用模块化、插件化架构。

---

## 当前阶段

### Phase 1: 框架实现 ⏳ IN_PROGRESS
目标：搭建基础框架，实现核心库模块

#### 任务清单
- [ ] 1.1 创建目录结构
- [ ] 1.2 实现 pgtool.sh（主入口）
- [ ] 1.3 实现 lib/core.sh（核心常量）
- [ ] 1.4 实现 lib/log.sh（日志系统）
- [ ] 1.5 实现 lib/util.sh（工具函数）
- [ ] 1.6 实现 lib/output.sh（输出格式化）
- [ ] 1.7 实现 lib/pg.sh（PostgreSQL 封装）
- [ ] 1.8 实现 lib/cli.sh（命令分发）
- [ ] 1.9 实现 lib/plugin.sh（插件管理）

#### 验收标准
- [ ] `./pgtool.sh --help` 显示帮助信息
- [ ] `./pgtool.sh --version` 显示版本
- [ ] 目录结构符合架构设计

---

### Phase 2: 命令组索引与帮助系统 📋 PENDING
目标：实现命令自动发现和帮助系统

#### 任务清单
- [ ] 2.1 创建 commands/check/index.sh
- [ ] 2.2 创建 commands/stat/index.sh
- [ ] 2.3 创建 commands/admin/index.sh
- [ ] 2.4 创建 commands/analyze/index.sh
- [ ] 2.5 实现全局帮助命令
- [ ] 2.6 实现组级帮助命令
- [ ] 2.7 实现命令补全脚本框架

#### 验收标准
- [ ] `pgtool --help` 显示所有命令组
- [ ] `pgtool check --help` 显示 check 组的命令
- [ ] 未知命令显示友好错误

---

### Phase 3: 第一个命令实现 (check xid) 📋 PENDING
目标：实现完整的命令流程作为模板

#### 任务清单
- [ ] 3.1 编写 sql/check/xid.sql
- [ ] 3.2 编写 commands/check/xid.sh
- [ ] 3.3 在 commands/check/index.sh 注册命令
- [ ] 3.4 实现阈值判断逻辑
- [ ] 3.5 支持不同输出格式

#### 验收标准
- [ ] `pgtool check xid` 能正常执行
- [ ] 显示 XID 年龄信息
- [ ] 超过阈值显示警告/危险
- [ ] 支持 `--format=json` 输出

---

### Phase 4: 扩展检查类命令 📋 PENDING
目标：完成 check 组的其他命令

#### 任务清单
- [ ] 4.1 check replication
- [ ] 4.2 check autovacuum
- [ ] 4.3 check connection
- [ ] 4.4 check storage

#### 验收标准
- [ ] 所有 check 命令可执行
- [ ] 每个命令有对应的 SQL 文件
- [ ] 命令帮助文档完整

---

### Phase 5: 统计类命令 📋 PENDING
目标：实现 stat 组命令

#### 任务清单
- [ ] 5.1 stat activity
- [ ] 5.2 stat locks
- [ ] 5.3 stat database
- [ ] 5.4 stat table
- [ ] 5.5 stat index

#### 验收标准
- [ ] 所有 stat 命令可执行
- [ ] 支持实时刷新模式（类似 top）

---

### Phase 6: 管理类命令 📋 PENDING
目标：实现 admin 组命令（危险操作需确认）

#### 任务清单
- [ ] 6.1 admin kill-blocking（带 --force 确认）
- [ ] 6.2 admin cancel-query
- [ ] 6.3 admin checkpoint
- [ ] 6.4 admin reload

#### 验收标准
- [ ] 危险操作默认需要确认
- [ ] 支持 --force 跳过确认
- [ ] 操作结果明确显示

---

### Phase 7: 分析类命令 📋 PENDING
目标：实现 analyze 组命令

#### 任务清单
- [ ] 7.1 analyze bloat
- [ ] 7.2 analyze missing-indexes
- [ ] 7.3 analyze slow-queries
- [ ] 7.4 analyze vacuum-stats

#### 验收标准
- [ ] 所有 analyze 命令可执行
- [ ] 提供可操作建议

---

### Phase 8: 配置与插件系统 📋 PENDING
目标：完善配置加载和插件机制

#### 任务清单
- [ ] 8.1 配置文件模板
- [ ] 8.2 环境变量支持
- [ ] 8.3 外部插件加载
- [ ] 8.4 插件示例

#### 验收标准
- [ ] 配置文件可被正确加载
- [ ] 优先级顺序正确
- [ ] 外部插件可被加载执行

---

### Phase 9: 测试 📋 PENDING
目标：建立测试体系

#### 任务清单
- [ ] 9.1 单元测试框架
- [ ] 9.2 lib/ 模块测试
- [ ] 9.3 命令测试（模拟环境）
- [ ] 9.4 集成测试（真实 PG 环境）
- [ ] 9.5 安装测试

#### 验收标准
- [ ] 核心函数有测试覆盖
- [ ] CI 可通过
- [ ] 文档说明如何运行测试

---

### Phase 10: 发布准备 📋 PENDING
目标：完成发布所需的文档和脚本

#### 任务清单
- [ ] 10.1 README.md 编写
- [ ] 10.2 安装脚本（install.sh）
- [ ] 10.3 Shell 补全脚本
- [ ] 10.4 使用手册（docs/USAGE.md）
- [ ] 10.5 开发手册（docs/DEVELOPMENT.md）
- [ ] 10.6 CHANGELOG.md
- [ ] 10.7 版本标签

#### 验收标准
- [ ] 新用户可通过 README 快速上手
- [ ] 安装脚本可正常运行
- [ ] 所有文档完整

---

## 开发原则

### 代码规范
- 使用 Bash strict mode: `set -euo pipefail`
- 所有函数加 `pgtool_` 前缀避免命名冲突
- 常量使用 `readonly` 定义
- 错误处理必须明确

### 提交规范
- 每个 Phase 独立分支
- 提交信息格式: `[phase-N] 描述`
- 完成一个 Phase 后标记并更新进度

### 测试要求
- 每个 lib 函数必须有基本测试
- 每个命令必须有输出验证
- 合并前必须通过测试

---

## 当前进行中的任务

**Phase 1: 框架实现**
- 状态: IN_PROGRESS
- 开始时间: 2026-03-31
- 预计完成: 1-2 小时

---

## 进度记录

| 日期 | 完成任务 | 备注 |
|------|---------|------|
| 2026-03-31 | 架构设计 | ARCHITECTURE.md 完成 |
| | | |

---

## 遇到的问题

| 问题 | 解决方案 | 状态 |
|------|---------|------|
| | | |

