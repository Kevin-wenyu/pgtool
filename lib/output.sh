#!/bin/bash
# lib/output.sh - 输出格式化系统

# 必须先加载 core.sh 和 log.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# 支持的格式
#==============================================================================

PGTOOL_VALID_FORMATS=("table" "csv" "html" "unaligned")

# 验证格式是否有效
pgtool_validate_format() {
    local format="$1"
    local valid

    for valid in "${PGTOOL_VALID_FORMATS[@]}"; do
        if [[ "$format" == "$valid" ]]; then
            return 0
        fi
    done

    pgtool_error "无效格式: $format"
    pgtool_info "支持的格式: ${PGTOOL_VALID_FORMATS[*]}"
    return 1
}

# 获取默认格式
pgtool_default_format() {
    echo "table"
}

#==============================================================================
# 表格格式化
#==============================================================================

# 使用 psql 的表格格式
pgtool_format_table() {
    local data="$1"

    if [[ -z "$data" ]] || [[ "$data" == "(0 rows)" ]]; then
        pgtool_info "无数据"
        return 0
    fi

    # 直接输出（假设数据已经是 psql 格式化的）
    echo "$data"
}

# 格式化带分隔符的表格
pgtool_format_box_table() {
    local -a headers=("$@")
    local max_cols=${#headers[@]}

    # 计算列宽
    local -a widths
    local i
    for i in "${!headers[@]}"; do
        widths[$i]=${#headers[$i]}
    done

    # 打印分隔线
    print_separator() {
        local char="$1"
        local line="+"
        for w in "${widths[@]}"; do
            line+="$(repeat_char "$char" $((w + 2)))+"
        done
        echo "$line"
    }

    # 打印行
    print_row() {
        local -a cols=("$@")
        local line="|"
        local i
        for i in "${!cols[@]}"; do
            printf -v cell " %-*s " "${widths[$i]}" "${cols[$i]}"
            line+="$cell|"
        done
        echo "$line"
    }

    # 输出表头
    print_separator "-"
    print_row "${headers[@]}"
    print_separator "="

    # 读取数据行并输出
    local line
    while IFS=$'\t' read -r -a cols; do
        print_row "${cols[@]:0:$max_cols}"
    done

    print_separator "-"
}

#==============================================================================
# JSON 格式化
#==============================================================================

# 简单的表格数据转 JSON
pgtool_format_json() {
    local data="$1"

    # 检查是否有数据
    if [[ -z "$data" ]] || [[ "$data" == "(0 rows)" ]]; then
        echo "[]"
        return 0
    fi

    # 使用 psql 的 json 格式（如果数据源支持）
    # 否则手动转换
    echo "$data"
}

# 将 psql 输出转换为 JSON
pgtool_to_json() {
    local -a headers=("$@")
    local first=true

    echo "["

    local line
    while IFS=$'\t' read -r -a values; do
        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi

        echo -n "  {"
        local i
        local inner_first=true
        for i in "${!headers[@]}"; do
            if [[ "$inner_first" == true ]]; then
                inner_first=false
            else
                echo -n ", "
            fi
            printf '"%s": "%s"' "${headers[$i]}" "${values[$i]}"
        done
        echo -n "}"
    done

    echo
    echo "]"
}

#==============================================================================
# CSV/TSV 格式化
#==============================================================================

pgtool_format_csv() {
    local data="$1"
    echo "$data" | sed 's/\t/,/g'
}

pgtool_format_tsv() {
    local data="$1"
    echo "$data"
}

# CSV 转义
pgtool_csv_escape() {
    local value="$1"

    # 如果包含逗号、引号或换行，需要转义
    if [[ "$value" == *[,\"\$'\n']* ]]; then
        value="${value//\"/\"\"}"
        value="\"$value\""
    fi

    echo "$value"
}

#==============================================================================
# 简单文本格式
#==============================================================================

pgtool_format_simple() {
    local data="$1"
    echo "$data"
}

#==============================================================================
# 主输出函数
#==============================================================================

# 格式化并输出数据
pgtool_output() {
    local data="$1"
    local format="${2:-${PGTOOL_FORMAT}}"

    # 验证格式
    if ! pgtool_validate_format "$format"; then
        format="table"
    fi

    case "$format" in
        table)
            pgtool_format_table "$data"
            ;;
        json)
            pgtool_format_json "$data"
            ;;
        csv)
            pgtool_format_csv "$data"
            ;;
        tsv)
            pgtool_format_tsv "$data"
            ;;
        simple)
            pgtool_format_simple "$data"
            ;;
        *)
            pgtool_format_table "$data"
            ;;
    esac
}

# 构建 psql 格式选项
pgtool_pset_args() {
    local format="${1:-${PGTOOL_FORMAT}}"

    case "$format" in
        table|aligned)
            echo "--pset=format=aligned --pset=border=2 --pset=pager=off"
            ;;
        csv)
            echo "--pset=format=csv --pset=tuples_only=on"
            ;;
        json)
            # PostgreSQL 18.x 不支持 json 格式，使用 unaligned 并手动转换
            echo "--pset=format=unaligned --pset=fieldsep='|' --pset=border=0 --pset=header --pset=pager=off"
            ;;
        html)
            echo "--pset=format=html"
            ;;
        unaligned|tsv|simple)
            echo "--pset=format=unaligned --pset=tuples_only=on"
            ;;
        *)
            echo "--pset=format=aligned --pset=border=2 --pset=pager=off"
            ;;
    esac
}

#==============================================================================
# 输出辅助
#==============================================================================

# 打印带标题的分隔块
pgtool_header() {
    local title="$1"
    local width="${2:-60}"

    echo
    echo "$(repeat_char "=" $width)"
    echo "  $title"
    echo "$(repeat_char "=" $width)"
}

# 打印小节标题
pgtool_section() {
    local title="$1"
    echo
    echo "--- $title ---"
}

# 打印键值对
pgtool_kv() {
    local key="$1"
    local value="$2"
    local width="${3:-20}"

    printf "%-${width}s: %s\n" "$key" "$value"
}

# 打印空行
pgtool_blank() {
    echo
}
