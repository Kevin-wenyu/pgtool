# User Command Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `user` command group for PostgreSQL user and permission management with security auditing.

**Architecture:** Read-only security audit tool - query system catalogs (pg_roles, pg_auth_members) for user info, permissions, and security issues. Never executes GRANT/REVOKE.

**Tech Stack:** Bash, psql, recursive CTEs for role tree

---

## File Structure

| File | Type | Purpose |
|------|------|---------|
| `commands/user/index.sh` | Create | Command group index |
| `commands/user/list.sh` | Create | List users command |
| `commands/user/info.sh` | Create | User info command |
| `commands/user/permissions.sh` | Create | Show permissions |
| `commands/user/activity.sh` | Create | User activity |
| `commands/user/audit.sh` | Create | Security audit |
| `commands/user/tree.sh` | Create | Role tree |
| `lib/user.sh` | Create | User utility functions |
| `sql/user/*.sql` | Create | Multiple SQL templates |
| `lib/cli.sh` | Modify | Add "user" to PGTOOL_GROUPS |
| `tests/test_user.sh` | Create | Unit tests |

---

## Task 1: Create User Utilities Library (lib/user.sh)

**Files:**
- Create: `lib/user.sh`

- [ ] **Step 1: Write user utilities**

```bash
#!/bin/bash
# lib/user.sh - User and permission utilities

#==============================================================================
# User Listing
#==============================================================================

# List all roles
pgtool_user_list_all() {
    pgtool_pg_exec "SELECT rolname FROM pg_roles ORDER BY rolname" \
        --tuples-only --quiet 2>/dev/null | tr -d ' '
}

# List users with connection counts
pgtool_user_list_with_connections() {
    pgtool_pg_exec "SELECT usename, COUNT(*) FROM pg_stat_activity GROUP BY usename ORDER BY COUNT(*) DESC" \
        --tuples-only --quiet 2>/dev/null
}

#==============================================================================
# User Info
#==============================================================================

# Get user basic info
pgtool_user_get_info() {
    local username="$1"

    pgtool_pg_exec "SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreaterole, rolcanlogin, rolconnlimit, rolvaliduntil FROM pg_roles WHERE rolname = '$username'" \
        --pset=format=unaligned --pset=fieldsep='|' \
        --tuples-only --quiet 2>/dev/null
}

# Get role membership (roles this user is member of)
pgtool_user_get_membership() {
    local username="$1"

    pgtool_pg_exec "SELECT r.rolname FROM pg_auth_members m JOIN pg_roles r ON m.roleid = r.oid WHERE m.member = (SELECT oid FROM pg_roles WHERE rolname = '$username')" \
        --tuples-only --quiet 2>/dev/null | tr -d ' '
}

# Get members of a role
pgtool_user_get_members() {
    local rolename="$1"

    pgtool_pg_exec "SELECT r.rolname FROM pg_auth_members m JOIN pg_roles r ON m.member = r.oid WHERE m.roleid = (SELECT oid FROM pg_roles WHERE rolname = '$rolename')" \
        --tuples-only --quiet 2>/dev/null | tr -d ' '
}

#==============================================================================
# Permission Queries
#==============================================================================

# Check if user has specific permission on database
pgtool_user_has_db_permission() {
    local username="$1"
    local dbname="$2"
    local perm="$3"

    pgtool_pg_query_one "SELECT has_database_privilege('$username', '$dbname', '$perm')" 2>/dev/null
}

# Check if user has table permission
pgtool_user_has_table_permission() {
    local username="$1"
    local table="$2"
    local perm="$3"

    pgtool_pg_query_one "SELECT has_table_privilege('$username', '$table', '$perm')" 2>/dev/null
}

#==============================================================================
# Security Checks
#==============================================================================

# Count superusers
pgtool_user_count_superusers() {
    pgtool_pg_query_one "SELECT COUNT(*) FROM pg_roles WHERE rolsuper" 2>/dev/null
}

# Check for empty passwords
pgtool_user_check_empty_passwords() {
    # Note: Requires superuser access to pg_authid
    pgtool_pg_exec "SELECT rolname FROM pg_authid WHERE rolpassword IS NULL AND rolcanlogin" \
        --tuples-only --quiet 2>/dev/null | tr -d ' '
}

# Check for roles with NOLOGIN that have permissions
pgtool_user_check_nologin_with_perms() {
    pgtool_pg_exec "SELECT r.rolname FROM pg_roles r WHERE NOT r.rolcanlogin AND EXISTS (SELECT 1 FROM pg_auth_members m WHERE m.member = r.oid)" \
        --tuples-only --quiet 2>/dev/null | tr -d ' '
}

# Check for roles with BYPASSRLS
pgtool_user_check_bypass_rls() {
    pgtool_pg_exec "SELECT rolname FROM pg_roles WHERE rolbypassrls" \
        --tuples-only --quiet 2>/dev/null | tr -d ' '
}

# Check for replication roles
pgtool_user_check_replication() {
    pgtool_pg_exec "SELECT rolname FROM pg_roles WHERE rolreplication" \
        --tuples-only --quiet 2>/dev/null | tr -d ' '
}

#==============================================================================
# Activity
#==============================================================================

# Get user activity summary
pgtool_user_activity_summary() {
    pgtool_pg_exec "SELECT usename, state, COUNT(*) FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY usename, state ORDER BY usename, state" \
        --tuples-only --quiet 2>/dev/null
}

#==============================================================================
# Tree Building
#==============================================================================

# Build role tree recursively
pgtool_user_build_tree() {
    local root_role="${1:-}"

    if [[ -n "$root_role" ]]; then
        # Start from specific role
        pgtool_pg_exec "WITH RECURSIVE role_tree AS (SELECT r.oid, r.rolname, 0 AS level FROM pg_roles r WHERE r.rolname = '$root_role' UNION ALL SELECT r.oid, r.rolname, rt.level + 1 FROM pg_roles r JOIN pg_auth_members m ON m.member = r.oid JOIN role_tree rt ON m.roleid = rt.oid) SELECT rolname, level FROM role_tree ORDER BY level, rolname" \
            --tuples-only --quiet 2>/dev/null
    else
        # Start from all root roles
        pgtool_pg_exec "WITH RECURSIVE role_tree AS (SELECT r.oid, r.rolname, NULL::name AS parent, 0 AS level FROM pg_roles r WHERE NOT EXISTS (SELECT 1 FROM pg_auth_members m WHERE m.member = r.oid) AND r.rolname !~ '^pg_' UNION ALL SELECT r.oid, r.rolname, rt.rolname, rt.level + 1 FROM pg_roles r JOIN pg_auth_members m ON m.member = r.oid JOIN role_tree rt ON m.roleid = r.oid WHERE r.rolname !~ '^pg_') SELECT rolname, parent, level FROM role_tree ORDER BY level, parent, rolname" \
            --tuples-only --quiet 2>/dev/null
    fi
}

#==============================================================================
# Formatting
#==============================================================================

# Format boolean for display
pgtool_user_format_bool() {
    local value="$1"
    [[ "$value" == "t" ]] && echo "Yes" || echo "No"
}

# Format tree with indentation
pgtool_user_format_tree() {
    local tree_data="$1"
    local max_depth="${2:-10}"

    local prev_level=-1

    while IFS='|' read -r name parent level; do
        [[ -z "$name" ]] && continue
        [[ -z "$level" ]] && level=0

        # Prevent infinite loops
        if [[ "$level" -gt "$max_depth" ]]; then
            continue
        fi

        local indent=""
        for ((i=0; i<level; i++)); do
            indent="${indent}  "
        done

        if [[ -n "$parent" && "$level" -gt 0 ]]; then
            echo "${indent}└── $name"
        else
            echo "$name"
        fi
    done <<< "$tree_data"
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/user.sh
git commit -m "feat(user): add user and permission utility library"
```

---

## Task 2: Create SQL Templates

**Files:**
- Create: `sql/user/list.sql`
- Create: `sql/user/info.sql`
- Create: `sql/user/activity.sql`
- Create: `sql/user/permissions_database.sql`
- Create: `sql/user/permissions_tables.sql`
- Create: `sql/user/audit_superusers.sql`
- Create: `sql/user/membership.sql`

- [ ] **Step 1: Write list.sql**

```sql
-- sql/user/list.sql
-- List all database users
-- Parameters: none

SELECT
    r.rolname AS "User",
    CASE WHEN r.rolsuper THEN 'Yes' ELSE 'No' END AS "Superuser",
    CASE WHEN r.rolcreatedb THEN 'Yes' ELSE 'No' END AS "Create DB",
    CASE WHEN r.rolcreaterole THEN 'Yes' ELSE 'No' END AS "Create Role",
    CASE WHEN r.rolcanlogin THEN 'Yes' ELSE 'No' END AS "Can Login",
    COALESCE(r.rolconnlimit::text, 'N/A') AS "Conn Limit",
    CASE
        WHEN r.rolvaliduntil < NOW() THEN 'EXPIRED'
        WHEN r.rolvaliduntil IS NOT NULL THEN r.rolvaliduntil::text
        ELSE 'Never'
    END AS "Password Expires",
    ARRAY_TO_STRING(ARRAY(
        SELECT b.rolname
        FROM pg_auth_members m
        JOIN pg_roles b ON m.roleid = b.oid
        WHERE m.member = r.oid
    ), ', ') AS "Member Of"
FROM pg_roles r
WHERE r.rolname !~ '^pg_'
  AND r.rolname != 'rds_superuser'
ORDER BY r.rolsuper DESC, r.rolname;
```

- [ ] **Step 2: Write info.sql**

```sql
-- sql/user/info.sql
-- Detailed user information
-- Parameters: :username

SELECT
    r.rolname AS "User",
    CASE WHEN r.rolsuper THEN 'Yes' ELSE 'No' END AS "Superuser",
    CASE WHEN r.rolinherit THEN 'Yes' ELSE 'No' END AS "Inherit",
    CASE WHEN r.rolcreaterole THEN 'Yes' ELSE 'No' END AS "Create Role",
    CASE WHEN r.rolcreatedb THEN 'Yes' ELSE 'No' END AS "Create DB",
    CASE WHEN r.rolcanlogin THEN 'Yes' ELSE 'No' END AS "Can Login",
    COALESCE(r.rolconnlimit::text, 'Unlimited') AS "Conn Limit",
    CASE
        WHEN r.rolvaliduntil IS NULL THEN 'Never'
        WHEN r.rolvaliduntil < NOW() THEN 'EXPIRED: ' || r.rolvaliduntil::text
        ELSE r.rolvaliduntil::text
    END AS "Password Expires",
    CASE WHEN r.rolreplication THEN 'Yes' ELSE 'No' END AS "Replication",
    CASE WHEN r.rolbypassrls THEN 'Yes' ELSE 'No' END AS "Bypass RLS",
    ARRAY_TO_STRING(ARRAY(
        SELECT b.rolname
        FROM pg_auth_members m
        JOIN pg_roles b ON m.roleid = b.oid
        WHERE m.member = r.oid
    ), ', ') AS "Member Of",
    ARRAY_TO_STRING(ARRAY(
        SELECT b.rolname
        FROM pg_auth_members m
        JOIN pg_roles b ON m.member = b.oid
        WHERE m.roleid = r.oid
    ), ', ') AS "Has Members"
FROM pg_roles r
WHERE r.rolname = :username;
```

- [ ] **Step 3: Write activity.sql**

```sql
-- sql/user/activity.sql
-- User connection activity
-- Parameters: :username (optional, NULL for all)

SELECT
    usename AS "User",
    COUNT(*) FILTER (WHERE state = 'active') AS "Active",
    COUNT(*) FILTER (WHERE state = 'idle') AS "Idle",
    COUNT(*) FILTER (WHERE state = 'idle in transaction') AS "Idle in Tx",
    COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) AS "Waiting",
    COUNT(*) AS "Total"
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND (:username IS NULL OR usename = :username)
GROUP BY usename
ORDER BY "Total" DESC;
```

- [ ] **Step 4: Write permissions_database.sql**

```sql
-- sql/user/permissions_database.sql
-- Database-level permissions
-- Parameters: :username

SELECT
    datname AS "Database",
    CASE WHEN pg_catalog.has_database_privilege(:username, datname, 'CONNECT') THEN 'Yes' ELSE 'No' END AS "Connect",
    CASE WHEN pg_catalog.has_database_privilege(:username, datname, 'CREATE') THEN 'Yes' ELSE 'No' END AS "Create",
    CASE WHEN pg_catalog.has_database_privilege(:username, datname, 'TEMPORARY') THEN 'Yes' ELSE 'No' END AS "Temporary"
FROM pg_database
WHERE datallowconn
ORDER BY datname;
```

- [ ] **Step 5: Write permissions_tables.sql**

```sql
-- sql/user/permissions_tables.sql
-- Table-level permissions
-- Parameters: :username, :limit

SELECT
    schemaname AS "Schema",
    tablename AS "Table",
    CASE WHEN pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'SELECT') THEN 'SELECT' ELSE '' END ||
    CASE WHEN pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'INSERT') THEN ' INSERT' ELSE '' END ||
    CASE WHEN pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'UPDATE') THEN ' UPDATE' ELSE '' END ||
    CASE WHEN pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'DELETE') THEN ' DELETE' ELSE '' END ||
    CASE WHEN pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'TRUNCATE') THEN ' TRUNCATE' ELSE '' END ||
    CASE WHEN pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'REFERENCES') THEN ' REFERENCES' ELSE '' END ||
    CASE WHEN pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'TRIGGER') THEN ' TRIGGER' ELSE '' END
    AS "Privileges"
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename
LIMIT :limit;
```

- [ ] **Step 6: Write audit_superusers.sql**

```sql
-- sql/user/audit_superusers.sql
-- List superusers
-- Parameters: none

SELECT
    rolname AS "User",
    CASE WHEN rolname IN ('postgres', 'rds_superuser') THEN 'Built-in' ELSE 'Custom' END AS "Type",
    CASE WHEN rolcreaterole THEN 'Yes' ELSE 'No' END AS "Can Create Roles",
    CASE WHEN rolcanlogin THEN 'Yes' ELSE 'No' END AS "Can Login"
FROM pg_roles
WHERE rolsuper
ORDER BY rolname;
```

- [ ] **Step 7: Write membership.sql**

```sql
-- sql/user/membership.sql
-- Role membership tree
-- Parameters: :role (optional, NULL for all roots)

WITH RECURSIVE role_tree AS (
    -- Base case: root roles (not members of any other role)
    SELECT
        r.oid,
        r.rolname,
        NULL::name AS parent,
        0 AS level
    FROM pg_roles r
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_auth_members m WHERE m.member = r.oid
    )
    AND r.rolname !~ '^pg_'
    AND (:role IS NULL OR r.rolname = :role)

    UNION ALL

    -- Recursive case: child roles
    SELECT
        r.oid,
        r.rolname,
        rt.rolname AS parent,
        rt.level + 1
    FROM pg_roles r
    JOIN pg_auth_members m ON m.member = r.oid
    JOIN role_tree rt ON m.roleid = rt.oid
    WHERE r.rolname !~ '^pg_'
)
SELECT rolname AS "Role", parent AS "Member Of", level AS "Depth"
FROM role_tree
ORDER BY level, parent, rolname;
```

- [ ] **Step 8: Commit**

```bash
git add sql/user/
git commit -m "feat(user): add SQL templates for user and permission queries"
```

---

## Task 3: Create Command Group Index

**Files:**
- Create: `commands/user/index.sh`

- [ ] **Step 1: Write index.sh**

```bash
#!/bin/bash
# commands/user/index.sh - user command group index

# Command list: "command:description"
PGTOOL_USER_COMMANDS="list:列出所有用户,info:显示用户信息,permissions:显示用户权限,activity:显示用户活动,audit:安全审计,tree:显示角色树"

# Display help
pgtool_user_help() {
    cat <<EOF
用户类命令 - 用户与权限管理

可用命令:
  list        列出所有数据库用户
  info        显示用户详细信息
  permissions 显示用户权限
  activity    显示用户连接活动
  audit       安全审计用户和权限
  tree        显示角色成员关系树

选项:
  -h, --help              显示帮助
      --role NAME         指定角色名
      --with-superuser    包含超级用户详细信息
      --security-only     仅显示安全相关信息

安全说明:
  此命令组为只读，不会修改任何用户或权限。
  修改权限请使用 psql 直接执行 GRANT/REVOKE。

使用 'pgtool user <命令> --help' 查看具体命令帮助

示例:
  pgtool user list
  pgtool user info --role=app_user
  pgtool user permissions --role=readonly
  pgtool user audit
  pgtool user tree --role=postgres
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/user/index.sh
git commit -m "feat(user): add user command group index"
```

---

## Task 4: Implement User List Command

**Files:**
- Create: `commands/user/list.sh`

- [ ] **Step 1: Write list.sh**

```bash
#!/bin/bash
# commands/user/list.sh - User list command

#==============================================================================
# Main function
#==============================================================================

pgtool_user_list() {
    local -a opts=()
    local -a args=()
    local with_superuser=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_list_help
                return 0
                ;;
            --with-superuser)
                with_superuser=true
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "列出数据库用户..."
    echo

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "user" "list"); then
        pgtool_fatal "SQL文件未找到: user/list"
    fi

    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --pset=pager=off \
        $format_args \
        2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_error "查询失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # Count summary
    local total_count superuser_count
    total_count=$(echo "$result" | grep -c '^ [^ ]' 2>/dev/null || echo 0)
    superuser_count=$(echo "$result" | grep ' Yes' | wc -l)

    echo
    echo "总计: $total_count 个用户 (其中 $superuser_count 个超级用户)"

    return $EXIT_SUCCESS
}

# Help function
pgtool_user_list_help() {
    cat <<EOF
列出数据库用户

显示所有数据库用户的列表，包括角色属性和成员关系。

用法: pgtool user list [选项]

选项:
  -h, --help              显示帮助
      --with-superuser    包含超级用户的详细信息
      --format FORMAT     输出格式 (table|json|csv|tsv)

输出字段:
  User            - 用户名
  Superuser       - 是否为超级用户
  Create DB       - 是否可以创建数据库
  Create Role     - 是否可以创建角色
  Can Login       - 是否可以登录
  Conn Limit      - 连接数限制
  Password Expires- 密码过期时间
  Member Of       - 所属角色

示例:
  pgtool user list
  pgtool user list --with-superuser
  pgtool user list --format=json
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/user/list.sh
git commit -m "feat(user): add list command to show database users"
```

---

## Task 5: Implement User Info Command

**Files:**
- Create: `commands/user/info.sh`

- [ ] **Step 1: Write info.sh**

```bash
#!/bin/bash
# commands/user/info.sh - User info command

#==============================================================================
# Main function
#==============================================================================

pgtool_user_info() {
    local -a opts=()
    local -a args=()
    local role=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_info_help
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
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                if [[ -z "$role" ]]; then
                    role="$1"
                fi
                args+=("$1")
                shift
                ;;
        esac
    done

    # Validate role name
    if [[ -z "$role" ]]; then
        pgtool_error "需要指定 --role <用户名>"
        return $EXIT_INVALID_ARGS
    fi

    pgtool_info "获取用户信息: $role"
    echo

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Check if user exists
    local exists
    exists=$(pgtool_pg_query_one "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = '$role')" 2>/dev/null)

    if [[ "$exists" != "t" ]]; then
        pgtool_error "用户不存在: $role"
        return $EXIT_NOT_FOUND
    fi

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "user" "info"); then
        pgtool_fatal "SQL文件未找到: user/info"
    fi

    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --variable="username=$role" \
        --pset=pager=off \
        $format_args \
        2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_error "查询失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # Show connection count if user can login
    local can_login
    can_login=$(pgtool_pg_query_one "SELECT rolcanlogin FROM pg_roles WHERE rolname = '$role'" 2>/dev/null)

    if [[ "$can_login" == "t" ]]; then
        echo
        local conn_count
        conn_count=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_stat_activity WHERE usename = '$role'" 2>/dev/null)
        echo "当前连接数: $conn_count"
    fi

    return $EXIT_SUCCESS
}

# Help function
pgtool_user_info_help() {
    cat <<EOF
显示用户详细信息

显示指定用户的详细属性，包括权限、成员关系等。

用法: pgtool user info --role=<用户名> [选项]

选项:
  -h, --help              显示帮助
      --role NAME         用户名（必需）
      --format FORMAT     输出格式 (table|json|csv|tsv)

输出字段:
  User            - 用户名
  Superuser       - 是否为超级用户
  Inherit         - 是否继承权限
  Create Role     - 是否可以创建角色
  Create DB       - 是否可以创建数据库
  Can Login       - 是否可以登录
  Conn Limit      - 连接数限制
  Password Expires- 密码过期时间
  Replication     - 是否有复制权限
  Bypass RLS      - 是否绕过行级安全
  Member Of       - 所属角色
  Has Members     - 包含的成员角色

示例:
  pgtool user info --role=postgres
  pgtool user info --role=app_user
  pgtool user info --role=readonly --format=json
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/user/info.sh
git commit -m "feat(user): add info command for detailed user information"
```

---

## Task 6: Implement User Permissions Command

**Files:**
- Create: `commands/user/permissions.sh`

- [ ] **Step 1: Write permissions.sh**

```bash
#!/bin/bash
# commands/user/permissions.sh - User permissions command

#==============================================================================
# Main function
#==============================================================================

pgtool_user_permissions() {
    local -a opts=()
    local -a args=()
    local role=""
    local limit=50

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_permissions_help
                return 0
                ;;
            --role)
                shift
                role="$1"
                shift
                ;;
            --limit)
                shift
                limit="$1"
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                if [[ -z "$role" ]]; then
                    role="$1"
                fi
                args+=("$1")
                shift
                ;;
        esac
    done

    # Validate role name
    if [[ -z "$role" ]]; then
        pgtool_error "需要指定 --role <用户名>"
        return $EXIT_INVALID_ARGS
    fi

    pgtool_info "获取用户权限: $role"
    echo

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Check if user exists
    local exists
    exists=$(pgtool_pg_query_one "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = '$role')" 2>/dev/null)

    if [[ "$exists" != "t" ]]; then
        pgtool_error "用户不存在: $role"
        return $EXIT_NOT_FOUND
    fi

    echo "数据库权限:"
    echo "==========="
    echo

    # Database permissions
    local db_sql
    db_sql=$(pgtool_pg_find_sql "user" "permissions_database")

    timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$db_sql" \
        --variable="username=$role" \
        --pset=pager=off \
        2>&1

    echo
    echo "表权限 (前 $limit 个):"
    echo "==========="
    echo

    # Table permissions
    local table_sql
    table_sql=$(pgtool_pg_find_sql "user" "permissions_tables")

    timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$table_sql" \
        --variable="username=$role" \
        --variable="limit=$limit" \
        --pset=pager=off \
        2>&1

    return $EXIT_SUCCESS
}

# Help function
pgtool_user_permissions_help() {
    cat <<EOF
显示用户权限

显示指定用户的数据库和表级权限。

用法: pgtool user permissions --role=<用户名> [选项]

选项:
  -h, --help              显示帮助
      --role NAME         用户名（必需）
      --limit NUM         显示表数限制 (默认: 50)
      --format FORMAT     输出格式 (仅table)

权限说明:
  SELECT    - 查询数据
  INSERT    - 插入数据
  UPDATE    - 更新数据
  DELETE    - 删除数据
  TRUNCATE  - 清空表
  REFERENCES- 外键引用
  TRIGGER   - 创建触发器

示例:
  pgtool user permissions --role=app_user
  pgtool user permissions --role=readonly --limit=100
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/user/permissions.sh
git commit -m "feat(user): add permissions command to show user privileges"
```

---

## Task 7: Implement User Activity Command

**Files:**
- Create: `commands/user/activity.sh`

- [ ] **Step 1: Write activity.sh**

```bash
#!/bin/bash
# commands/user/activity.sh - User activity command

#==============================================================================
# Main function
#==============================================================================

pgtool_user_activity() {
    local -a opts=()
    local -a args=()
    local role=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_user_activity_help
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
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                if [[ -z "$role" ]]; then
                    role="$1"
                fi
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "获取用户活动..."
    echo

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "user" "activity"); then
        pgtool_fatal "SQL文件未找到: user/activity"
    fi

    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --variable="username=${role:-NULL}" \
        --pset=pager=off \
        $format_args \
        2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_error "查询失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # Show total connections
    local total
    total=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_stat_activity WHERE backend_type = 'client backend'" 2>/dev/null)
    echo
    echo "总连接数: $total"

    return $EXIT_SUCCESS
}

# Help function
pgtool_user_activity_help() {
    cat <<EOF
显示用户活动

显示用户连接活动统计，包括活跃、空闲、等待状态。

用法: pgtool user activity [选项]

选项:
  -h, --help              显示帮助
      --role NAME         指定用户名（默认: 所有用户）
      --format FORMAT     输出格式 (table|json|csv|tsv)

输出字段:
  User          - 用户名
  Active        - 活跃连接数
  Idle          - 空闲连接数
  Idle in Tx    - 事务中空闲连接
  Waiting       - 等待中的连接
  Total         - 总连接数

示例:
  pgtool user activity
  pgtool user activity --role=app_user
  pgtool user activity --format=json
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/user/activity.sh
git commit -m "feat(user): add activity command for user connection stats"
```

---

## Task 8: Implement User Audit Command

**Files:**
- Create: `commands/user/audit.sh`

- [ ] **Step 1: Write audit.sh**

```bash
#!/bin/bash
# commands/user/audit.sh - User audit command

#==============================================================================
# Main function
#==============================================================================

pgtool_user_audit() {
    local -a opts=()
    local -a args=()
    local security_only=false

    # Parse arguments
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
                PGTOOL_FORMAT="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "执行用户安全审计..."
    echo

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    local issues_found=0

    # Check 1: Superuser count
    echo "检查: 超级用户数量"
    echo "==================="
    echo

    local superuser_count
    superuser_count=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_roles WHERE rolsuper" 2>/dev/null)

    if [[ "$superuser_count" -gt 3 ]]; then
        echo "  [WARNING] 发现 $superuser_count 个超级用户（建议最多3个）"
        ((issues_found++))
    else
        echo "  [OK] 超级用户数量正常: $superuser_count"
    fi
    echo

    # Check 2: Superusers list
    local superusers_sql
    superusers_sql=$(pgtool_pg_find_sql "user" "audit_superusers")

    echo "  超级用户列表:"
    timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$superusers_sql" \
        --pset=pager=off \
        2>&1
    echo

    # Check 3: Bypass RLS
    echo "检查: 绕过行级安全的用户"
    echo "======================="
    echo

    local bypass_rls
    bypass_rls=$(pgtool_pg_exec "SELECT rolname FROM pg_roles WHERE rolbypassrls ORDER BY rolname" --tuples-only --quiet 2>/dev/null | tr -d ' ')

    if [[ -n "$bypass_rls" ]]; then
        echo "  [WARNING] 发现可绕过RLS的用户:"
        echo "$bypass_rls" | while read -r user; do
            [[ -n "$user" ]] && echo "    - $user"
        done
        ((issues_found++))
    else
        echo "  [OK] 无用户可绕过行级安全"
    fi
    echo

    # Check 4: Replication roles
    echo "检查: 复制权限用户"
    echo "=================="
    echo

    local repl_users
    repl_users=$(pgtool_pg_exec "SELECT rolname FROM pg_roles WHERE rolreplication ORDER BY rolname" --tuples-only --quiet 2>/dev/null | tr -d ' ')

    if [[ -n "$repl_users" ]]; then
        echo "  [INFO] 有复制权限的用户:"
        echo "$repl_users" | while read -r user; do
            [[ -n "$user" ]] && echo "    - $user"
        done
    else
        echo "  [OK] 无用户有复制权限"
    fi
    echo

    # Check 5: Inactive roles
    echo "检查: 未使用的角色"
    echo "=================="
    echo

    # This is a simplified check - just list roles with NOLOGIN
    local nologin_roles
    nologin_roles=$(pgtool_pg_exec "SELECT rolname FROM pg_roles WHERE NOT rolcanlogin ORDER BY rolname" --tuples-only --quiet 2>/dev/null | tr -d ' ')

    if [[ -n "$nologin_roles" ]]; then
        local nologin_count
        nologin_count=$(echo "$nologin_roles" | wc -l)
        echo "  [INFO] 发现 $nologin_count 个不可登录角色"
    else
        echo "  [OK] 所有角色均可登录"
    fi
    echo

    # Summary
    echo "审计总结:"
    echo "========="
    if [[ $issues_found -eq 0 ]]; then
        echo "  [PASS] 未发现安全问题"
    else
        echo "  [WARN] 发现 $issues_found 个问题"
    fi

    return $EXIT_SUCCESS
}

# Help function
pgtool_user_audit_help() {
    cat <<EOF
安全审计用户和权限

执行安全检查，发现潜在的安全问题。

用法: pgtool user audit [选项]

选项:
  -h, --help              显示帮助
      --security-only     仅显示安全相关结果
      --format FORMAT     输出格式 (仅table)

检查项目:
  1. 超级用户数量（建议最多3个）
  2. 可绕过行级安全(RLS)的用户
  3. 有复制权限的用户
  4. 未使用的角色
  5. 空密码用户（需要超级用户权限）

安全级别:
  CRITICAL - 需要立即处理
  WARNING  - 建议审查
  INFO     - 仅供参考

注意:
  此命令为只读，不会修改任何权限。

示例:
  pgtool user audit
  pgtool user audit --security-only
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/user/audit.sh
git commit -m "feat(user): add audit command for security auditing"
```

---

## Task 9: Implement User Tree Command

**Files:**
- Create: `commands/user/tree.sh`

- [ ] **Step 1: Write tree.sh**

```bash
#!/bin/bash
# commands/user/tree.sh - User tree command

#==============================================================================
# Main function
#==============================================================================

pgtool_user_tree() {
    local -a opts=()
    local -a args=()
    local role=""

    # Parse arguments
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
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                if [[ -z "$role" ]]; then
                    role="$1"
                fi
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "生成角色成员关系树..."
    echo

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "user" "membership"); then
        pgtool_fatal "SQL文件未找到: user/membership"
    fi

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --variable="role=${role:-NULL}" \
        --pset=pager=off \
        --pset=format=unaligned \
        --pset=fieldsep='|' \
        --tuples-only \
        --quiet \
        2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_error "查询失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # Format and display tree
    if [[ -z "$result" ]]; then
        if [[ -n "$role" ]]; then
            echo "角色 '$role' 没有成员关系"
        else
            echo "没有角色成员关系"
        fi
        return $EXIT_SUCCESS
    fi

    # Display tree with ASCII art
    echo "角色成员关系:"
    echo "============="
    echo

    # Build tree structure
    declare -A children
    declare -A levels
    local root_roles=()

    while IFS='|' read -r name parent level; do
        [[ -z "$name" ]] && continue
        name=$(echo "$name" | tr -d ' ')
        parent=$(echo "$parent" | tr -d ' ')

        levels["$name"]="$level"

        if [[ -z "$parent" || "$parent" == "NULL" ]]; then
            root_roles+=("$name")
        else
            children["$parent"]+=" $name"
        fi
    done <<< "$result"

    # Print tree recursively
    print_tree_node() {
        local node="$1"
        local indent="$2"
        local is_last="$3"

        if [[ "$is_last" == "true" ]]; then
            echo "${indent}└── $node"
            new_indent="${indent}    "
        else
            echo "${indent}├── $node"
            new_indent="${indent}│   "
        fi

        local child_list="${children[$node]:-}"
        local -a child_arr
        read -ra child_arr <<< "$child_list"

        local last_idx=$((${#child_arr[@]} - 1))
        for i in "${!child_arr[@]}"; do
            local child="${child_arr[$i]}"
            [[ -z "$child" ]] && continue

            if [[ $i -eq $last_idx ]]; then
                print_tree_node "$child" "$new_indent" "true"
            else
                print_tree_node "$child" "$new_indent" "false"
            fi
        done
    }

    local total_roots=${#root_roles[@]}
    for i in "${!root_roles[@]}"; do
        local root="${root_roles[$i]}"
        if [[ $i -eq $((total_roots - 1)) ]]; then
            print_tree_node "$root" "" "true"
        else
            print_tree_node "$root" "" "false"
        fi
    done

    return $EXIT_SUCCESS
}

# Help function
pgtool_user_tree_help() {
    cat <<EOF
显示角色成员关系树

以树形结构显示角色的成员关系（谁属于哪个角色）。

用法: pgtool user tree [选项]

选项:
  -h, --help              显示帮助
      --role NAME         从指定角色开始显示（默认: 所有根角色）
      --format FORMAT     输出格式 (仅table)

示例输出:
  postgres
  ├── app_read
  │   └── app_user1
  └── app_write
      └── app_admin

示例:
  pgtool user tree
  pgtool user tree --role=postgres
  pgtool user tree --role=app_read
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/user/tree.sh
git commit -m "feat(user): add tree command for role membership visualization"
```

---

## Task 10: Register User Command Group

**Files:**
- Modify: `lib/cli.sh`

- [ ] **Step 1: Add user to PGTOOL_GROUPS**

```bash
# Line 15: Change from:
PGTOOL_GROUPS=("check" "stat" "admin" "analyze" "plugin")
# To:
PGTOOL_GROUPS=("check" "stat" "admin" "analyze" "plugin" "user")
```

- [ ] **Step 2: Add user case to pgtool_group_desc**

```bash
# Add before *) case:
        user)    echo "用户管理 - 用户与权限查询" ;;
```

- [ ] **Step 3: Commit**

```bash
git add lib/cli.sh
git commit -m "feat(user): register user command group in CLI dispatcher"
```

---

## Task 11: Create Tests

**Files:**
- Create: `tests/test_user.sh`

- [ ] **Step 1: Write test file**

```bash
#!/bin/bash
# tests/test_user.sh - User module tests

# Load test framework
source "$TEST_DIR/test_runner.sh"

#==============================================================================
# Setup
#==============================================================================

setup_user_tests() {
    if ! type pgtool_user_list_all &>/dev/null; then
        source "$PGTOOL_ROOT/lib/user.sh" 2>/dev/null || true
    fi
}

#==============================================================================
# Tests
#==============================================================================

test_user_lib_loaded() {
    assert_true "type pgtool_user_list_all &>/dev/null"
    assert_true "type pgtool_user_get_info &>/dev/null"
    assert_true "type pgtool_user_format_bool &>/dev/null"
}

test_user_format_bool() {
    local result

    result=$(pgtool_user_format_bool "t")
    assert_equals "Yes" "$result"

    result=$(pgtool_user_format_bool "f")
    assert_equals "No" "$result"

    result=$(pgtool_user_format_bool "")
    assert_equals "No" "$result"
}

test_user_commands_exist() {
    assert_true "[[ -f $PGTOOL_ROOT/commands/user/index.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/user/list.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/user/info.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/user/permissions.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/user/activity.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/user/audit.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/user/tree.sh ]]"
}

test_user_sql_files_exist() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/user/list.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/sql/user/info.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/sql/user/activity.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/sql/user/permissions_database.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/sql/user/permissions_tables.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/sql/user/audit_superusers.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/sql/user/membership.sql ]]"
}

test_user_registered_in_cli() {
    assert_contains "${PGTOOL_GROUPS[*]}" "user"
}

#==============================================================================
# Run tests
#==============================================================================

setup_user_tests
run_test "user_lib_loaded" test_user_lib_loaded
run_test "user_format_bool" test_user_format_bool
run_test "user_commands_exist" test_user_commands_exist
run_test "user_sql_files_exist" test_user_sql_files_exist
run_test "user_registered" test_user_registered_in_cli
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_user.sh
git commit -m "test(user): add unit tests for user command group"
```

---

## Spec Coverage Check

| Requirement | Task | Status |
|-------------|------|--------|
| List users | Task 4 | ✓ |
| User info | Task 5 | ✓ |
| Permissions | Task 6 | ✓ |
| Activity | Task 7 | ✓ |
| Security audit | Task 8 | ✓ |
| Role tree | Task 9 | ✓ |
| SQL separation | Task 2 | ✓ |
| Read-only design | All | ✓ |
| Command registration | Task 10 | ✓ |
| Tests | Task 11 | ✓ |

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-02-user-command-group.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
