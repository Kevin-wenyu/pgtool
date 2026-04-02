#!/bin/bash
# commands/user/audit.sh - 用户安全审计

#==============================================================================
# 主函数
#==============================================================================

pgtool_user_audit() {
    local security_only=false
    local format="${PGTOOL_FORMAT:-table}"
    local issue_count=0
    local -a issues=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_audit_help
                return 0
                ;;
            --security-only)
                security_only=true
                shift
                ;;
            --format)
                shift
                format="$1"
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                # 全局选项，跳过参数值
                shift
                shift
                ;;
            -*)
                pgtool_warn "未知选项: $1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "执行用户安全审计..."
    echo ""

    # 测试连接
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    #==========================================================================
    # 检查1: 超级用户数量
    #==========================================================================
    local superuser_count
    superuser_count=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_roles WHERE rolsuper")

    if [[ $? -ne 0 ]]; then
        pgtool_error "无法获取超级用户数量"
        return $EXIT_SQL_ERROR
    fi

    echo "========================================"
    echo "  用户安全审计报告"
    echo "========================================"
    echo ""

    echo "[1/5] 超级用户检查"
    echo "----------------------------------------"
    pgtool_kv "超级用户总数" "$superuser_count"

    if [[ "$superuser_count" -gt 3 ]]; then
        pgtool_warning "超级用户数量超过建议值(3)"
        issues+=("超级用户过多: $superuser_count (建议不超过3个)")
        ((issue_count++))
    else
        pgtool_success "超级用户数量正常"
    fi
    echo ""

    #==========================================================================
    # 检查2: 超级用户列表
    #==========================================================================
    echo "[2/5] 超级用户详细信息"
    echo "----------------------------------------"

    local sql_file
    if sql_file=$(pgtool_pg_find_sql "user" "audit_superusers"); then
        local format_args
        format_args=$(pgtool_pset_args "$format")

        local superusers_result
        superusers_result=$(timeout "$PGTOOL_TIMEOUT" psql \
            "${PGTOOL_CONN_OPTS[@]}" \
            --file="$sql_file" \
            --pset=pager=off \
            $format_args \
            2>&1)

        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            echo "$superusers_result"
        else
            pgtool_warn "无法获取超级用户详细信息: $superusers_result"
        fi
    else
        pgtool_warn "SQL文件未找到: user/audit_superusers"
    fi
    echo ""

    #==========================================================================
    # 检查3: 绕过RLS的用户
    #==========================================================================
    echo "[3/5] 绕过行级安全策略(Bypass RLS)检查"
    echo "----------------------------------------"

    local bypass_rls_count
    bypass_rls_count=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_roles WHERE rolbypassrls")

    if [[ $? -eq 0 ]]; then
        pgtool_kv "绕过RLS用户数量" "$bypass_rls_count"

        if [[ "$bypass_rls_count" -gt 0 ]]; then
            pgtool_warning "发现可绕过行级安全策略的用户"
            issues+=("RLS绕过用户: $bypass_rls_count 个")
            ((issue_count++))

            # 显示详细信息
            local bypass_rls_users
            bypass_rls_users=$(pgtool_pg_exec "SELECT rolname, rolsuper FROM pg_roles WHERE rolbypassrls" --tuples-only --quiet)
            echo "详细列表:"
            echo "$bypass_rls_users"
        else
            pgtool_success "无用户可绕过RLS"
        fi
    else
        pgtool_warn "无法获取RLS绕过信息"
    fi
    echo ""

    #==========================================================================
    # 检查4: 复制用户
    #==========================================================================
    echo "[4/5] 复制权限用户检查"
    echo "----------------------------------------"

    local repl_count
    repl_count=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_roles WHERE rolreplication")

    if [[ $? -eq 0 ]]; then
        pgtool_kv "复制权限用户数量" "$repl_count"

        if [[ "$repl_count" -gt 0 ]]; then
            pgtool_warning "发现具有复制权限的用户"
            issues+=("复制权限用户: $repl_count 个")
            ((issue_count++))

            # 显示详细信息
            local repl_users
            repl_users=$(pgtool_pg_exec "SELECT rolname, rolsuper FROM pg_roles WHERE rolreplication" --tuples-only --quiet)
            echo "详细列表:"
            echo "$repl_users"
        else
            pgtool_success "无复制权限用户"
        fi
    else
        pgtool_warn "无法获取复制权限信息"
    fi
    echo ""

    #==========================================================================
    # 检查5: 非活动角色 (NOLOGIN)
    #==========================================================================
    echo "[5/5] 非活动角色检查"
    echo "----------------------------------------"

    local inactive_count
    inactive_count=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_roles WHERE NOT rolcanlogin")

    if [[ $? -eq 0 ]]; then
        pgtool_kv "非活动角色数量" "$inactive_count"

        if [[ "$inactive_count" -gt 0 ]]; then
            echo "说明: 这些角色无法直接登录，通常用于权限组"

            # 如果不是仅安全模式，显示详细信息
            if [[ "$security_only" == false ]]; then
                echo "非活动角色列表:"
                local inactive_roles
                inactive_roles=$(pgtool_pg_exec "SELECT rolname FROM pg_roles WHERE NOT rolcanlogin ORDER BY rolname" --tuples-only --quiet)
                echo "$inactive_roles"
            fi
        else
            pgtool_success "无非活动角色"
        fi
    else
        pgtool_warn "无法获取非活动角色信息"
    fi
    echo ""

    #==========================================================================
    # 总结
    #==========================================================================
    echo "========================================"
    echo "  审计总结"
    echo "========================================"

    if [[ "$issue_count" -eq 0 ]]; then
        echo ""
        pgtool_success "未发现安全问题"
        echo ""
        return $EXIT_SUCCESS
    else
        echo ""
        pgtool_warning "发现 $issue_count 个安全问题"
        echo ""
        echo "问题详情:"
        local i=1
        local issue
        for issue in "${issues[@]}"; do
            echo "  $i. $issue"
            ((i++))
        done
        echo ""

        # 返回非零状态码表示发现安全问题
        return 1
    fi
}

#==============================================================================
# 帮助函数
#==============================================================================

pgtool_user_audit_help() {
    cat <<EOF
用户安全审计

执行全面的用户和角色安全审计，检查以下项目:
1. 超级用户数量 (警告阈值: >3)
2. 超级用户详细信息
3. 可绕过行级安全策略(RLS)的用户
4. 具有复制权限的用户
5. 非活动角色(NOLOGIN)

用法: pgtool user audit [选项]

选项:
  -h, --help           显示帮助
      --security-only  仅显示安全问题(隐藏正常信息)
      --format FORMAT  输出格式 (table|json|csv|tsv)

安全检查说明:
  超级用户过多      - PostgreSQL超级用户具有完全控制权，建议不超过3个
  绕过RLS          - 可绕过行级安全策略查看所有数据，需严格审查
  复制权限          - 可复制整个数据库，可能泄露敏感数据
  非活动角色        - 用于权限组的角色，本身无法登录

输出说明:
  超级用户检查会显示每个超级用户的详细权限配置
  发现问题时会显示黄色警告图标
  无问题时会显示绿色成功图标

示例:
  pgtool user audit
  pgtool user audit --security-only
  pgtool user audit --format=json

返回值:
  0 - 无安全问题
  1 - 发现安全问题
  其他 - 执行错误
EOF
}
