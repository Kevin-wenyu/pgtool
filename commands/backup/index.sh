#!/bin/bash
# commands/backup/index.sh - 备份命令组索引

# 命令列表: "命令名:描述"
PGTOOL_BACKUP_COMMANDS="status:显示备份状态,verify:验证备份完整性,archive:检查WAL归档状态,list:列出可用备份,info:显示备份详情"

# 显示帮助
pgtool_backup_help() {
    cat <<EOF
备份类命令 - PostgreSQL备份管理

可用命令:
  status        显示备份状态
  verify        验证备份完整性
  archive       检查WAL归档状态
  list          列出可用备份
  info          显示备份详情

选项:
  -h, --help      显示帮助
      --tool      指定备份工具 (pgbackrest|barman|pg_dump)
      --stanza    pgBackRest: 指定stanza名称
      --server    Barman: 指定server名称

备份工具优先级:
  pgBackRest > Barman > pg_dump
  默认自动检测已安装的备份工具

使用 'pgtool backup <命令> --help' 查看具体命令帮助

示例:
  pgtool backup status
  pgtool backup status --tool=pgbackrest --stanza=mydb
  pgtool backup verify --tool=barman --server=prod
  pgtool backup list --format=json
  pgtool backup info --stanza=mydb
EOF
}
