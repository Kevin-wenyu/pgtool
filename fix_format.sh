#!/bin/bash
# fix_format.sh - 批量修复 --format 参数支持

for file in commands/*/*.sh; do
    [[ -f "$file" ]] || continue

    # 检查是否已经有 --format 处理
    if grep -q "\-\-format)" "$file"; then
        echo "跳过 (已修复): $file"
        continue
    fi

    # 检查是否有参数解析
    if grep -q "while \[\[ \$# -gt 0 \]\]" "$file"; then
        # 在 -h|--help) 后添加 --format 处理
        sed -i '' '/-h|--help)/,/;;/{ /;;/a\
            --format)\
                shift\
                PGTOOL_FORMAT="$1"\
                shift\
                ;;\
            --timeout|--color|--log-level|--host|--port|--user|--dbname)\
                shift\
                shift\
                ;;
}' "$file"
        echo "修复: $file"
    fi
done

echo "完成！"
