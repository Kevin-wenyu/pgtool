#!/bin/bash
# commands/user/index.sh - user 命令组索引

# 命令列表: "命令名:描述"
PGTOOL_USER_COMMANDS="list:列出所有用户,info:显示用户信息,permissions:显示用户权限,activity:显示用户活动,audit:安全审计,tree:显示角色树"

# 显示帮助
pgtool_user_help() {
    cat <<EOF
用户管理类命令 - 用户、角色和权限管理

可用命令:
  list          列出所有用户
  info          显示指定用户详细信息
  permissions   显示用户权限概览
  activity      显示用户当前活动
  audit         用户安全审计
  tree          显示角色继承树

选项:
  -h, --help    显示帮助

注意: user 命令组是只读操作，不会修改用户或权限。

使用 'pgtool user <命令> --help' 查看具体命令帮助

示例:
  pgtool user list
  pgtool user info postgres
  pgtool user permissions myuser
  pgtool user activity --format=json
  pgtool user audit
  pgtool user tree
EOF
}
