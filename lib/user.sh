#!/bin/bash
# lib/user.sh - User and permission utility functions

# 必须先加载 core.sh 和 log.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# User Listing Functions
#==============================================================================

# List all roles, returns usernames
pgtool_user_list_all() {
    pgtool_pg_exec "SELECT rolname FROM pg_roles ORDER BY rolname" \
        --tuples-only --quiet 2>/dev/null | tr -d ' '
}

# List users with connection counts
pgtool_user_list_with_connections() {
    local sql="
SELECT r.rolname AS username,
       COALESCE(counts.active_conns, 0) AS active_connections,
       r.rolconnlimit AS connection_limit,
       CASE
           WHEN r.rolconnlimit = -1 THEN 'Unlimited'
           WHEN r.rolconnlimit = 0 THEN 'No connections'
           ELSE CAST(COALESCE(counts.active_conns, 0) AS TEXT) || ' / ' || CAST(r.rolconnlimit AS TEXT)
       END AS usage
FROM pg_roles r
LEFT JOIN (
    SELECT usename, COUNT(*) AS active_conns
    FROM pg_stat_activity
    WHERE backend_type = 'client backend'
    GROUP BY usename
) counts ON r.rolname = counts.usename
WHERE r.rolcanlogin
ORDER BY COALESCE(counts.active_conns, 0) DESC, r.rolname"

    pgtool_pg_exec "$sql" 2>/dev/null
}

#==============================================================================
# User Info Functions
#==============================================================================

# Get basic user info (superuser, canlogin, etc)
# Usage: pgtool_user_get_info <username>
pgtool_user_get_info() {
    local username="$1"

    if [[ -z "$username" ]]; then
        pgtool_error "用户名不能为空"
        return $EXIT_INVALID_ARGS
    fi

    local sql="
SELECT rolname AS username,
       rolsuper AS is_superuser,
       rolinherit AS can_inherit,
       rolcreaterole AS can_create_role,
       rolcreatedb AS can_create_db,
       rolcanlogin AS can_login,
       rolreplication AS is_replication,
       rolbypassrls AS bypass_rls,
       rolconnlimit AS connection_limit,
       COALESCE(rolvaliduntil::TEXT, 'Never') AS password_expires
FROM pg_roles
WHERE rolname = '$username'"

    pgtool_pg_exec "$sql" 2>/dev/null
}

# Get roles this user is member of
# Usage: pgtool_user_get_membership <username>
pgtool_user_get_membership() {
    local username="$1"

    if [[ -z "$username" ]]; then
        pgtool_error "用户名不能为空"
        return $EXIT_INVALID_ARGS
    fi

    local sql="
SELECT r.rolname AS role_name,
       m.admin_option AS is_admin
FROM pg_auth_members m
JOIN pg_roles r ON m.roleid = r.oid
JOIN pg_roles u ON m.member = u.oid
WHERE u.rolname = '$username'
ORDER BY r.rolname"

    pgtool_pg_exec "$sql" 2>/dev/null
}

# Get members of a role
# Usage: pgtool_user_get_members <rolename>
pgtool_user_get_members() {
    local rolename="$1"

    if [[ -z "$rolename" ]]; then
        pgtool_error "角色名不能为空"
        return $EXIT_INVALID_ARGS
    fi

    local sql="
SELECT u.rolname AS member_name,
       m.admin_option AS is_admin
FROM pg_auth_members m
JOIN pg_roles r ON m.roleid = r.oid
JOIN pg_roles u ON m.member = u.oid
WHERE r.rolname = '$rolename'
ORDER BY u.rolname"

    pgtool_pg_exec "$sql" 2>/dev/null
}

#==============================================================================
# Permission Query Functions
#==============================================================================

# Check if user has database permission
# Usage: pgtool_user_has_db_permission <username> <dbname> <perm>
# perms: CONNECT, CREATE, TEMPORARY, TEMP, ALL
pgtool_user_has_db_permission() {
    local username="$1"
    local dbname="$2"
    local perm="${3:-CONNECT}"

    if [[ -z "$username" ]] || [[ -z "$dbname" ]]; then
        pgtool_error "用户名和数据库名不能为空"
        return $EXIT_INVALID_ARGS
    fi

    local sql="SELECT has_database_privilege('$username', '$dbname', '$perm')"
    local result
    result=$(pgtool_pg_query_one "$sql" 2>/dev/null)

    [[ "$result" == "t" ]]
}

# Check if user has table permission
# Usage: pgtool_user_has_table_permission <username> <table> <perm>
# perms: SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, ALL
pgtool_user_has_table_permission() {
    local username="$1"
    local table="$2"
    local perm="${3:-SELECT}"

    if [[ -z "$username" ]] || [[ -z "$table" ]]; then
        pgtool_error "用户名和表名不能为空"
        return $EXIT_INVALID_ARGS
    fi

    local sql="SELECT has_table_privilege('$username', '$table', '$perm')"
    local result
    result=$(pgtool_pg_query_one "$sql" 2>/dev/null)

    [[ "$result" == "t" ]]
}

#==============================================================================
# Security Check Functions
#==============================================================================

# Count superusers
pgtool_user_count_superusers() {
    local sql="SELECT COUNT(*) FROM pg_roles WHERE rolsuper"
    pgtool_pg_query_one "$sql" 2>/dev/null
}

# Find users with empty passwords
pgtool_user_check_empty_passwords() {
    local sql="
SELECT rolname AS username,
       CASE WHEN rolvaliduntil IS NULL THEN 'No expiration'
            ELSE 'Expires: ' || rolvaliduntil::TEXT
       END AS password_status
FROM pg_roles
WHERE rolcanlogin
  AND (rolvaliduntil IS NULL OR rolvaliduntil < NOW())
  AND NOT rolsuper
ORDER BY rolname"

    pgtool_pg_exec "$sql" 2>/dev/null
}

# Find NOLOGIN roles with permissions
pgtool_user_check_nologin_with_perms() {
    local sql="
SELECT r.rolname AS role_name,
       r.rolcreaterole AS can_create_role,
       r.rolcreatedb AS can_create_db,
       r.rolreplication AS is_replication,
       r.rolbypassrls AS bypass_rls,
       COALESCE(array_length(array_agg(m.member), 1), 0) AS member_count
FROM pg_roles r
LEFT JOIN pg_auth_members m ON r.oid = m.roleid
WHERE NOT r.rolcanlogin
  AND (r.rolcreaterole OR r.rolcreatedb OR r.rolreplication OR r.rolbypassrls)
GROUP BY r.oid, r.rolname, r.rolcreaterole, r.rolcreatedb, r.rolreplication, r.rolbypassrls
ORDER BY r.rolname"

    pgtool_pg_exec "$sql" 2>/dev/null
}

# Find roles with BYPASSRLS
pgtool_user_check_bypass_rls() {
    local sql="
SELECT rolname AS role_name,
       rolsuper AS is_superuser,
       rolcanlogin AS can_login,
       CASE WHEN rolcanlogin THEN 'User' ELSE 'Group role' END AS role_type
FROM pg_roles
WHERE rolbypassrls
ORDER BY rolcanlogin, rolname"

    pgtool_pg_exec "$sql" 2>/dev/null
}

# Find replication roles
pgtool_user_check_replication() {
    local sql="
SELECT rolname AS role_name,
       rolsuper AS is_superuser,
       rolcanlogin AS can_login,
       CASE WHEN rolcanlogin THEN 'User' ELSE 'Group role' END AS role_type
FROM pg_roles
WHERE rolreplication
ORDER BY rolcanlogin, rolname"

    pgtool_pg_exec "$sql" 2>/dev/null
}

#==============================================================================
# Activity Functions
#==============================================================================

# Get user activity summary
pgtool_user_activity_summary() {
    local sql="
SELECT COALESCE(usename, 'unknown') AS username,
       COUNT(*) AS total_connections,
       COUNT(*) FILTER (WHERE state = 'active') AS active_queries,
       COUNT(*) FILTER (WHERE state = 'idle') AS idle_connections,
       COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction,
       COALESCE(EXTRACT(EPOCH FROM MAX(NOW() - query_start)))::INTEGER AS max_query_time_secs
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY usename
ORDER BY total_connections DESC"

    pgtool_pg_exec "$sql" 2>/dev/null
}

#==============================================================================
# Tree Building Functions
#==============================================================================

# Build role tree using recursive CTE
# Usage: pgtool_user_build_tree [root_role]
# If root_role is empty, shows all roles
pgtool_user_build_tree() {
    local root_role="${1:-}"

    local sql
    if [[ -n "$root_role" ]]; then
        # Build tree starting from specific role
        sql="
WITH RECURSIVE role_tree AS (
    -- Base case: the root role
    SELECT r.oid, r.rolname, r.rolsuper, r.rolcanlogin,
           0 AS depth,
           r.rolname::TEXT AS path
    FROM pg_roles r
    WHERE r.rolname = '$root_role'

    UNION ALL

    -- Recursive case: members of each role
    SELECT r.oid, r.rolname, r.rolsuper, r.rolcanlogin,
           rt.depth + 1,
           rt.path || ' -> ' || r.rolname
    FROM pg_roles r
    JOIN pg_auth_members m ON m.member = r.oid
    JOIN role_tree rt ON m.roleid = rt.oid
    WHERE rt.depth < 10  -- Prevent infinite loops
)
SELECT depth,
       rolname AS role_name,
       CASE WHEN rolsuper THEN 'Yes' ELSE 'No' END AS is_superuser,
       CASE WHEN rolcanlogin THEN 'User' ELSE 'Role' END AS role_type,
       path AS hierarchy
FROM role_tree
ORDER BY path"
    else
        # Show all role relationships
        sql="
WITH RECURSIVE role_tree AS (
    -- Base case: roles that aren't members of any other role (or top-level)
    SELECT r.oid, r.rolname, r.rolsuper, r.rolcanlogin,
           0 AS depth,
           r.rolname::TEXT AS path,
           ARRAY[r.oid] AS visited
    FROM pg_roles r
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_auth_members m WHERE m.member = r.oid
    )

    UNION ALL

    -- Recursive case: roles that are members of roles in the tree
    SELECT r.oid, r.rolname, r.rolsuper, r.rolcanlogin,
           rt.depth + 1,
           rt.path || ' -> ' || r.rolname,
           rt.visited || r.oid
    FROM pg_roles r
    JOIN pg_auth_members m ON m.member = r.oid
    JOIN role_tree rt ON m.roleid = rt.oid
    WHERE NOT r.oid = ANY(rt.visited)  -- Prevent cycles
      AND rt.depth < 10
)
SELECT depth,
       rolname AS role_name,
       CASE WHEN rolsuper THEN 'Yes' ELSE 'No' END AS is_superuser,
       CASE WHEN rolcanlogin THEN 'User' ELSE 'Role' END AS role_type,
       path AS hierarchy
FROM role_tree
ORDER BY path"
    fi

    pgtool_pg_exec "$sql" 2>/dev/null
}

#==============================================================================
# Formatting Functions
#==============================================================================

# Format boolean for display (t->Yes, f->No)
# Usage: pgtool_user_format_bool <value>
pgtool_user_format_bool() {
    local value="$1"

    case "$value" in
        t|true|1|yes)
            echo "Yes"
            ;;
        f|false|0|no)
            echo "No"
            ;;
        *)
            echo "$value"
            ;;
    esac
}

# Format tree data with indentation
# Usage: pgtool_user_format_tree <tree_data> [max_depth]
# Input: expects data from pgtool_user_build_tree with depth column
pgtool_user_format_tree() {
    local tree_data="$1"
    local max_depth="${2:-10}"

    if [[ -z "$tree_data" ]] || [[ "$tree_data" == "(0 rows)" ]]; then
        echo "No role tree data found"
        return 0
    fi

    # Parse and format with indentation
    local line
    local prev_depth=0

    echo "$tree_data" | while IFS='|' read -r depth role_name is_superuser role_type hierarchy; do
        # Trim whitespace
        depth=$(echo "$depth" | tr -d ' ')

        # Skip header lines
        if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
            continue
        fi

        # Check max depth
        if [[ "$depth" -gt "$max_depth" ]]; then
            continue
        fi

        # Build indentation
        local indent=""
        local i
        for ((i=0; i<depth; i++)); do
            indent="${indent}  "
        done

        # Choose connector based on depth
        local connector=""
        if [[ "$depth" -gt 0 ]]; then
            connector="└─ "
        fi

        # Output formatted line
        echo "${indent}${connector}${role_name} (${role_type})"
    done
}
