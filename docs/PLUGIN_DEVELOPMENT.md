# pgtool 插件开发指南

## 快速开始

### 1. 创建插件目录

```bash
mkdir -p ~/.pgtool/plugins/myplugin/commands
```

### 2. 创建插件配置

编辑 `~/.pgtool/plugins/myplugin/plugin.conf`：

```bash
PLUGIN_NAME="myplugin"
PLUGIN_VERSION="1.0.0"
PLUGIN_DESCRIPTION="我的第一个插件"
PLUGIN_DEPENDS="pgtool>=0.1.0"
PLUGIN_COMMANDS="mycmd:我的命令"
```

### 3. 创建命令

编辑 `~/.pgtool/plugins/myplugin/commands/mycmd.sh`：

```bash
pgtool_myplugin_mycmd() {
    echo "Hello from my plugin!"
}
```

### 4. 使用

```bash
pgtool myplugin mycmd
```

## 插件 API

### 可用的库函数

插件可以访问 pgtool 的所有库函数：

```bash
# 日志
pgtool_info "信息消息"
pgtool_warn "警告消息"
pgtool_error "错误消息"
pgtool_success "成功消息"

# PostgreSQL
pgtool_pg_exec "SELECT 1"
pgtool_pg_exec_file "path/to/sql.sql"
pgtool_pg_test_connection

# 工具
confirm "确认操作?"
is_int "$value"
trim "$string"
```

### 命令参数处理

```bash
pgtool_myplugin_mycmd() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                # 显示帮助
                return 0
                ;;
            --option)
                shift
                local value="$1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}
```

## 最佳实践

1. **命名规范**
   - 插件名使用小写字母和连字符
   - 命令名使用小写字母和连字符
   - 函数名使用下划线

2. **错误处理**
   - 检查依赖是否满足
   - 返回适当的退出码

3. **帮助信息**
   - 每个命令都应提供 `--help`
   - 说明命令用途和用法

4. **SQL 文件**
   - 复杂查询应放在 sql/ 目录
   - 使用 `pgtool_pg_find_sql` 加载
