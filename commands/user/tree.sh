#!/bin/bash
# commands/user/tree.sh - 显示角色继承树

#==============================================================================
# 主函数
#==============================================================================

pgtool_user_tree() {
    local -a opts=()
    local -a args=()
    local role=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_tree_help
                return 0
                ;;
            --role)
                shift
                role="$1"
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                # 全局选项，跳过参数值
                shift
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # 如果没有通过 --role 指定，使用第一个位置参数
    if [[ -z "$role" && ${#args[@]} -gt 0 ]]; then
        role="${args[0]}"
    fi

    pgtool_info "显示角色继承树..."
    echo ""

    # 查找 SQL 文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "user" "membership"); then
        pgtool_fatal "SQL文件未找到: user/membership"
    fi

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 执行 SQL
    local result
    local psql_var
    if [[ -n "$role" ]]; then
        psql_var="--variable=role='$role'"
    else
        psql_var="--variable=role=NULL"
    fi

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        $psql_var \
        --pset=format=unaligned --pset=fieldsep="|" --tuples-only --pset=pager=off \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # 检查是否有数据
    if [[ -z "$result" ]] || [[ "$result" == "(0 rows)" ]]; then
        if [[ -n "$role" ]]; then
            pgtool_warn "未找到角色: $role"
        else
            pgtool_warn "未找到任何角色"
        fi
        return $EXIT_NOT_FOUND
    fi

    # 格式化并输出树形结构
    pgtool_user_tree_format "$result"

    return $EXIT_SUCCESS
}

#==============================================================================
# 格式化树形输出 (兼容 bash 3.2)
#==============================================================================

pgtool_user_tree_format() {
    local data="$1"

    # 使用临时文件存储数据（bash 3.2 不支持关联数组）
    local tmpdir=$(mktemp -d)
    local children_file="$tmpdir/children"
    local depth_file="$tmpdir/depth"
    local roots_file="$tmpdir/roots"

    touch "$children_file" "$depth_file" "$roots_file"

    # 解析数据
    # 格式: role_name|member_of|depth
    local line role_name member_of depth
    while IFS='|' read -r role_name member_of depth; do
        # 去除空白
        role_name=$(echo "$role_name" | tr -d ' ')
        member_of=$(echo "$member_of" | tr -d ' ')
        depth=$(echo "$depth" | tr -d ' ')

        [[ -z "$role_name" ]] && continue

        # 记录深度
        echo "$role_name $depth" >> "$depth_file"

        # 记录父子关系
        if [[ -z "$member_of" ]]; then
            # 根角色
            echo "$role_name" >> "$roots_file"
        else
            # 子角色 - 添加到父角色的子列表
            # 格式: parent child
            echo "$member_of $role_name" >> "$children_file"
        fi
    done <<< "$data"

    # 如果没有根角色，找出所有角色作为根
    if [[ ! -s "$roots_file" ]]; then
        echo "$data" | while IFS='|' read -r role_name member_of depth; do
            role_name=$(echo "$role_name" | tr -d ' ')
            [[ -z "$role_name" ]] && continue
            echo "$role_name"
        done >> "$roots_file"
    fi

    # 递归打印树
    local total_count
    total_count=$(echo "$data" | grep -v '^$' | wc -l | tr -d ' ')

    local first_root=true
    local root
    while read -r root; do
        [[ -z "$root" ]] && continue
        if [[ "$first_root" == "true" ]]; then
            _pgtool_tree_print_node "$root" "" true "$children_file"
            first_root=false
        else
            _pgtool_tree_print_node "$root" "" true "$children_file"
        fi
    done < "$roots_file"

    # 清理临时文件
    rm -rf "$tmpdir"

    echo ""
    echo "--- 共 $total_count 个角色 ---"
}

# 递归打印树节点
# $1: 当前节点名称
# $2: 前缀
# $3: 是否为最后一个子节点 (true/false)
# $4: 子节点关系文件
_pgtool_tree_print_node() {
    local node="$1"
    local prefix="$2"
    local is_last="$3"
    local children_file="$4"

    # 打印当前节点
    if [[ -z "$prefix" ]]; then
        # 根节点
        echo "$node"
    else
        # 子节点
        local connector
        if [[ "$is_last" == "true" ]]; then
            connector="└── "
        else
            connector="├── "
        fi
        echo "${prefix}${connector}${node}"
    fi

    # 获取子节点列表
    local -a childs=()
    if [[ -s "$children_file" ]]; then
        while read -r line; do
            local parent child
            parent=$(echo "$line" | awk '{print $1}')
            child=$(echo "$line" | awk '{print $2}')
            if [[ "$parent" == "$node" ]]; then
                childs+=("$child")
            fi
        done < "$children_file"
    fi

    # 递归打印子节点
    local child_count=${#childs[@]}
    if [[ $child_count -gt 0 ]]; then
        local new_prefix
        if [[ "$is_last" == "true" ]]; then
            new_prefix="${prefix}    "
        else
            new_prefix="${prefix}│   "
        fi

        local i=0
        for child in "${childs[@]}"; do
            local child_is_last="false"
            if [[ $i -eq $((child_count - 1)) ]]; then
                child_is_last="true"
            fi

            _pgtool_tree_print_node "$child" "$new_prefix" "$child_is_last" "$children_file"
            ((i++))
        done
    fi
}

#==============================================================================
# 帮助函数
#==============================================================================

pgtool_user_tree_help() {
    cat <<EOF
显示角色继承树

以树形结构显示数据库角色的继承关系，包括：
- 根角色（没有父角色的角色）
- 角色层次结构（使用 ASCII 艺术显示缩进）
- 所有子角色及其父角色关系

用法: pgtool user tree [角色名] [选项]
   或: pgtool user tree --role=<角色名> [选项]

选项:
  -h, --help          显示帮助
      --role ROLE     指定起始角色名（仅显示该角色及其子树）
      --format FORMAT 输出格式（目前仅支持默认格式）

输出格式:
  默认使用 ASCII 艺术显示树形结构：
    - 根角色显示在第一列
    - 子角色使用 "├── " 或 "└── " 前缀缩进显示
    - 使用 "│   " 表示分支继续

示例:
  pgtool user tree           # 显示所有角色的继承树
  pgtool user tree admin     # 仅显示 admin 角色的子树
  pgtool user tree --role=admin

说明:
  - 系统角色（pg_ 开头）和 RDS 超级用户被排除
  - 仅显示当前数据库可见的角色
  - 如果指定了角色名，则从该角色开始向下显示其子树
EOF
}
