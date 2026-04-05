#!/bin/bash
# commands/check/index.sh - check 命令组索引

# 命令列表: "命令名:描述"
PGTOOL_CHECK_COMMANDS="xid:检查事务ID年龄,replication:检查流复制状态,autovacuum:检查autovacuum状态,connection:检查连接数,cache-hit:检查缓存命中率,long-tx:检查长事务,tablespace:检查表空间使用,replication-lag:检查复制延迟"

# 显示帮助
pgtool_check_help() {
    cat <<EOF
检查类命令 - 健康检查

可用命令:
  xid           检查事务ID年龄，预警XID回卷风险
  replication   检查流复制状态
  autovacuum    检查autovacuum状态
  connection    检查连接数使用情况
  cache-hit     检查缓存命中率
  long-tx       检查运行中的长事务
  tablespace    检查表空间使用情况
  replication-lag 检查主从复制延迟

选项:
  -h, --help    显示帮助

使用 'pgtool check <命令> --help' 查看具体命令帮助

示例:
  pgtool check xid
  pgtool check replication --format=json
  pgtool check connection --threshold=80
EOF
}
