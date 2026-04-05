#!/bin/bash
# commands/stat/index.sh - stat 命令组索引

PGTOOL_STAT_COMMANDS="activity:查看活动会话,locks:查看锁等待,database:查看数据库统计,table:查看表统计,indexes:查看索引统计,waits:查看等待事件"

pgtool_stat_help() {
    cat <<EOF
统计类命令 - 查看数据库统计信息

可用命令:
  activity      查看当前活动会话
  locks         查看锁等待情况
  database      查看数据库级统计
  table         查看表级统计
  indexes       查看索引使用情况
  waits         查看等待事件统计

选项:
  -h, --help    显示帮助

使用 'pgtool stat <命令> --help' 查看具体命令帮助

示例:
  pgtool stat activity
  pgtool stat locks --format=json
  pgtool stat database
EOF
}
