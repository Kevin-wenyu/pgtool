#!/bin/bash
# commands/monitor/index.sh - monitor 命令组索引

# 命令列表: "命令名:描述"
PGTOOL_MONITOR_COMMANDS="queries:实时监控活跃查询,connections:实时监控连接数,replication:实时监控复制延迟"

# 显示帮助
pgtool_monitor_help() {
    cat <<EOF
监控类命令 - 实时监控数据库状态

可用命令:
  queries       实时监控活跃查询，显示执行时间、SQL语句等
  connections   实时监控连接数变化
  replication   实时监控主从复制延迟

选项:
  -h, --help       显示帮助
  -i, --interval   刷新间隔（秒，默认2）
  -l, --limit      显示条目数限制（默认20）
  --once           只运行一次，不循环刷新

使用 'pgtool monitor <命令> --help' 查看具体命令帮助

示例:
  pgtool monitor queries
  pgtool monitor queries -i 1 -l 10
  pgtool monitor connections --once
  pgtool monitor replication -i 5

交互模式:
  实时监控运行时，按 'q' 键退出
EOF
}
