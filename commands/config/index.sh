#!/bin/bash
# commands/config/index.sh - config 命令组索引

# 命令列表: "命令名:描述"
PGTOOL_CONFIG_COMMANDS="analyze:分析配置并提供建议,diff:比较配置差异,get:获取参数值,set:生成设置命令,reset:显示重置命令,export:导出配置"

# 显示帮助
pgtool_config_help() {
    cat <<EOF
配置类命令 - 参数管理与分析

可用命令:
  analyze       分析当前配置并提供优化建议
  diff          比较当前配置与推荐值的差异
  get           获取指定参数值
  set           生成ALTER SYSTEM设置命令（需--dry-run）
  reset         生成参数重置命令（需--dry-run）
  export        导出配置为指定格式

选项:
  -h, --help          显示帮助
  --category=<cat>    按类别过滤（memory/storage/network/query）
  --changed-only      仅显示已修改的配置
  --recommend         显示推荐值和建议

提示:
  set/reset命令默认使用--dry-run模式，仅显示将要执行的SQL
  实际执行请移除--dry-run选项

使用 'pgtool config <命令> --help' 查看具体命令帮助

示例:
  pgtool config analyze
  pgtool config diff --category=memory
  pgtool config get shared_buffers
  pgtool config set shared_buffers=4GB --dry-run
  pgtool config export --format=json
EOF
}
