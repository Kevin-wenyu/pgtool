# pgtool 插件示例

这是一个演示如何创建 pgtool 插件的示例。

## 插件结构

```
plugins/example/
├── plugin.conf          # 插件配置
└── commands/
    ├── hello.sh        # 示例命令
    └── version.sh      # 版本命令
```

## 配置文件 (plugin.conf)

必需变量：
- `PLUGIN_NAME` - 插件名称（必需）
- `PLUGIN_VERSION` - 版本号
- `PLUGIN_DESCRIPTION` - 描述
- `PLUGIN_DEPENDS` - 依赖（格式: "package>=version"）
- `PLUGIN_COMMANDS` - 提供的命令

## 命令实现

命令文件放在 `commands/` 目录下，命名规范：
- 文件名使用下划线：`my_command.sh`
- 函数名：`pgtool_<plugin>_<command>`

示例：
```bash
pgtool_example_hello() {
    # 命令逻辑
    echo "Hello!"
}
```

## 安装插件

1. 将插件复制到插件目录：
```bash
cp -r plugins/example ~/.pgtool/plugins/
```

2. 重启 pgtool 即可加载

## 使用插件命令

```bash
pgtool example hello
pgtool example hello --name=World
pgtool example version
```

## 开发自己的插件

1. 复制 example 目录：
```bash
cp -r plugins/example plugins/myplugin
```

2. 修改 `plugin.conf` 中的信息

3. 在 `commands/` 目录添加命令脚本

4. 测试插件
