#!/bin/bash
# commands/admin/index.sh - admin 命令组索引

PGTOOL_ADMIN_COMMANDS="kill-blocking:终止阻塞会话,cancel-query:取消查询,checkpoint:触发检查点,reload:重载配置,rotate-log:轮换日志文件"

pgtool_admin_help() {
    cat <<EOF
管理类命令 - 执行管理操作

⚠️  注意: 这些命令会修改数据库状态，请谨慎使用

可用命令:
  kill-blocking   终止阻塞其他会话的进程
  cancel-query    取消正在执行的查询
  checkpoint      触发检查点
  reload          重载配置文件
  rotate-log      轮换日志文件

选项:
  -h, --help      显示帮助
      --force     跳过确认提示

使用 'pgtool admin <命令> --help' 查看具体命令帮助

示例:
  pgtool admin kill-blocking --pid=12345
  pgtool admin cancel-query --pid=12345 --force
  pgtool admin checkpoint
  pgtool admin rotate-log

警告:
  kill-blocking 和 cancel-query 会终止/取消正在执行的查询，
  可能导致事务回滚。请在执行前确认影响范围。
EOF
}
