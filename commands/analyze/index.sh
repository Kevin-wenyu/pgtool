#!/bin/bash
# commands/analyze/index.sh - analyze 命令组索引

PGTOOL_ANALYZE_COMMANDS="bloat:分析表膨胀,index-usage:索引使用分析,missing-indexes:查找缺失索引,slow-queries:分析慢查询,vacuum-stats:查看vacuum统计"

pgtool_analyze_help() {
    cat <<EOF
分析类命令 - 诊断分析问题

可用命令:
  bloat           分析表和索引膨胀
  index-usage     索引使用分析
  missing-indexes 查找可能的缺失索引
  slow-queries    分析慢查询
  vacuum-stats    查看vacuum统计信息

选项:
  -h, --help      显示帮助

使用 'pgtool analyze <命令> --help' 查看具体命令帮助

示例:
  pgtool analyze bloat
  pgtool analyze index-usage
  pgtool analyze missing-indexes --format=json
  pgtool analyze slow-queries
  pgtool analyze vacuum-stats
EOF
}
