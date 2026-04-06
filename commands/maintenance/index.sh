#!/bin/bash
# commands/maintenance/index.sh - Maintenance command group

PGTOOL_MAINTENANCE_COMMANDS="vacuum:执行VACUUM操作清理表,reindex:重建索引,analyze:更新表统计信息"

pgtool_maintenance_help() {
    cat <<EOF
维护类命令 - PostgreSQL数据库维护操作

可用命令:
  vacuum      执行VACUUM操作清理死亡元组
  reindex     重建索引消除膨胀
  analyze     更新表统计信息

使用 'pgtool maintenance <命令> --help' 查看具体命令帮助
EOF
}
