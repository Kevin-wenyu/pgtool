# Implementation Plan: pgtool user command group

## Task Type
- [x] Backend (→ Codex)
- [ ] Frontend (→ Gemini)
- [ ] Fullstack (→ Parallel)

## Overview
Add a new `user` command group to pgtool for PostgreSQL user and permission management. This provides DBAs with tools to list users, analyze permissions, check security, and manage access control.

## Technical Solution

### Architecture
1. **New command group**: `commands/user/` directory
2. **Permission analysis**: Query system catalogs for role and permission info
3. **Security scanning**: Check for security issues (superusers, weak passwords)
4. **Permission visualization**: Show role hierarchies and permission chains
5. **Audit support**: Track user activity and connections

### Commands
1. `user list` - List all database users/roles
2. `user info` - Show detailed user information
3. `user permissions` - Show user permissions and grants
4. `user activity` - Show user connection activity
5. `user audit` - Security audit for users and permissions
6. `user tree` - Show role membership tree

### Options
- `--role NAME` - Filter by specific role
- `--with-superuser` - Include superuser info
- `--security-only` - Show only security-relevant info
- `--format` - Output format (table, json)
- All standard global options

## Implementation Steps

### Step 1: Create command group infrastructure
**File**: `commands/user/index.sh`
```bash
PGTOOL_USER_COMMANDS="list:列出所有用户,info:显示用户信息,permissions:显示用户权限,activity:显示用户活动,audit:安全审计用户,tree:显示角色树"

pgtool_user_help() {
    # Help text for user commands
}
```

### Step 2: Add user to CLI dispatcher
**File**: `lib/cli.sh:L15`
- Add "user" to `PGTOOL_GROUPS` array
- Add "user" case to `pgtool_group_desc()`

### Step 3: Create user utilities library
**File**: `lib/user.sh`
```bash
# User listing
pgtool_user_list_all()             # List all roles
pgtool_user_list_with_conn()       # List users with connection counts

# User info
pgtool_user_get_info()             # Get detailed user info
pgtool_user_get_membership()       # Get role membership

# Permissions
pgtool_user_get_permissions()      # Get all permissions for user
pgtool_user_get_table_perms()      # Get table-level permissions
pgtool_user_get_schema_perms()     # Get schema-level permissions
pgtool_user_get_database_perms()   # Get database-level permissions

# Security checks
pgtool_user_check_security()       # Run security checks
pgtool_user_check_superusers()     # List superusers
pgtool_user_check_nologin_roles()  # List roles with NOLOGIN
pgtool_user_check_empty_passwords() # Check for empty passwords
pgtool_user_check_default_privs()  # Check default privileges

# Role tree
pgtool_user_build_tree()           # Build role membership tree
pgtool_user_format_tree()          # Format tree for display

# Activity
pgtool_user_get_activity()         # Get user activity from pg_stat_activity
```

### Step 4: Implement user list command
**File**: `commands/user/list.sh`

```bash
pgtool_user_list() {
    # Parse options: --with-superuser, --format
    # Query pg_roles for all roles
    # Show: rolname, rolsuper, rolcreatedb, rolcreaterole, rolinherit, canlogin
    # Optionally show connection counts from pg_stat_activity
}
```

**File**: `sql/user/list.sql`
```sql
SELECT
    r.rolname as username,
    r.rolsuper as is_superuser,
    r.rolcreatedb as can_create_db,
    r.rolcreaterole as can_create_role,
    r.rolinherit as inherits,
    r.rolcanlogin as can_login,
    r.rolconnlimit as conn_limit,
    CASE WHEN r.rolvaliduntil < NOW() THEN 'EXPIRED'
         WHEN r.rolvaliduntil IS NOT NULL THEN r.rolvaliduntil::text
         ELSE 'NEVER' END as password_expires,
    ARRAY(
        SELECT b.rolname
        FROM pg_catalog.pg_auth_members m
        JOIN pg_catalog.pg_roles b ON (m.roleid = b.oid)
        WHERE m.member = r.oid
    ) as member_of
FROM pg_catalog.pg_roles r
WHERE r.rolname !~ '^pg_'
  AND r.rolname != 'rds_superuser'
ORDER BY r.rolname;
```

### Step 5: Implement user info command
**File**: `commands/user/info.sh`
```bash
pgtool_user_info() {
    # Parse: --role USERNAME (required)
    # Get detailed info:
        # Basic role attributes
        # Membership in other roles
        # Members of this role
        # Connection count
        # Last connection time (if track_activities)
    # Show in formatted output
}
```

**File**: `sql/user/info.sql`
```sql
SELECT
    r.rolname,
    r.rolsuper,
    r.rolinherit,
    r.rolcreaterole,
    r.rolcreatedb,
    r.rolcanlogin,
    r.rolconnlimit,
    r.rolvaliduntil,
    r.rolreplication,
    r.rolbypassrls,
    ARRAY(
        SELECT b.rolname
        FROM pg_catalog.pg_auth_members m
        JOIN pg_catalog.pg_roles b ON (m.roleid = b.oid)
        WHERE m.member = r.oid
    ) as member_of,
    ARRAY(
        SELECT b.rolname
        FROM pg_catalog.pg_auth_members m
        JOIN pg_catalog.pg_roles b ON (m.member = b.oid)
        WHERE m.roleid = r.oid
    ) as has_members
FROM pg_catalog.pg_roles r
WHERE r.rolname = :username;
```

### Step 6: Implement user permissions command
**File**: `commands/user/permissions.sh`
```bash
pgtool_user_permissions() {
    # Parse: --role USERNAME (required)
    # Show permissions at different levels:
        # Database level
        # Schema level
        # Table level
        # Sequence level
        # Function level
    # Show effective permissions (including inherited)
}
```

**File**: `sql/user/permissions_database.sql`
```sql
SELECT datname,
       pg_catalog.has_database_privilege(:username, datname, 'CONNECT') as connect,
       pg_catalog.has_database_privilege(:username, datname, 'CREATE') as create,
       pg_catalog.has_database_privilege(:username, datname, 'TEMPORARY') as temporary
FROM pg_database
WHERE datallowconn
ORDER BY datname;
```

**File**: `sql/user/permissions_tables.sql`
```sql
SELECT schemaname, tablename,
       pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'SELECT') as select,
       pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'INSERT') as insert,
       pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'UPDATE') as update,
       pg_catalog.has_table_privilege(:username, schemaname || '.' || tablename, 'DELETE') as delete
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename
LIMIT :limit;
```

### Step 7: Implement user activity command
**File**: `commands/user/activity.sh`
```bash
pgtool_user_activity() {
    # Parse: --role USERNAME (optional, default all)
    # Query pg_stat_activity grouped by usename
    # Show: username, active_count, idle_count, idle_in_transaction_count
    # Show detailed connections if --detail
}
```

**File**: `sql/user/activity.sql`
```sql
SELECT
    usename as username,
    COUNT(*) FILTER (WHERE state = 'active') as active,
    COUNT(*) FILTER (WHERE state = 'idle') as idle,
    COUNT(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction,
    COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) as waiting,
    COUNT(*) as total
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND (:username IS NULL OR usename = :username)
GROUP BY usename
ORDER BY total DESC;
```

### Step 8: Implement user audit command
**File**: `commands/user/audit.sh`
```bash
pgtool_user_audit() {
    # Run security checks:
        # Superusers (flag if too many)
        # Users with empty passwords (md5 '', trust auth)
        # Users with BYPASSRLS (if row level security used)
        # Users with REPLICATION privilege
        # Roles with NOLOGIN that have permissions
        # Unused roles (no connections recently)
        # Roles with dangerous default privileges
    # Output: findings by severity (CRITICAL, WARNING, INFO)
}
```

**File**: `sql/user/audit_superusers.sql`
```sql
SELECT rolname as username,
       'CRITICAL' as severity,
       'Superuser with elevated privileges' as issue
FROM pg_roles
WHERE rolsuper
  AND rolname NOT IN ('postgres', 'rds_superuser');
```

**File**: `sql/user/audit_empty_passwords.sql`
```sql
SELECT rolname as username,
       'WARNING' as severity,
       'Role may have empty password' as issue
FROM pg_authid
WHERE rolpassword IS NULL
  AND rolcanlogin;
```

### Step 9: Implement user tree command
**File**: `commands/user/tree.sh`
```bash
pgtool_user_tree() {
    # Parse: --role USERNAME (optional root)
    # Build role membership tree recursively
    # Display as ASCII tree:
    #   postgres
    #   ├── app_read
    #   │   ├── app_user1
    #   │   └── app_user2
    #   └── app_write
    #       └── app_admin
}
```

**File**: `sql/user/membership.sql`
```sql
WITH RECURSIVE role_tree AS (
    -- Root roles (not members of any other role)
    SELECT r.oid, r.rolname, NULL::name as member_of, 0 as level
    FROM pg_roles r
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_auth_members m WHERE m.member = r.oid
    )
    AND r.rolname !~ '^pg_'

    UNION ALL

    -- Child roles
    SELECT r.oid, r.rolname, rt.rolname as member_of, rt.level + 1
    FROM pg_roles r
    JOIN pg_auth_members m ON m.member = r.oid
    JOIN role_tree rt ON m.roleid = rt.oid
    WHERE r.rolname !~ '^pg_'
)
SELECT rolname, member_of, level
FROM role_tree
ORDER BY level, member_of, rolname;
```

### Step 10: Create SQL templates
**Files**: `sql/user/*.sql`

- `sql/user/list.sql` - User list query
- `sql/user/info.sql` - User detail query
- `sql/user/activity.sql` - User activity query
- `sql/user/permissions_database.sql` - Database permissions
- `sql/user/permissions_tables.sql` - Table permissions
- `sql/user/audit_superusers.sql` - Superuser audit
- `sql/user/audit_empty_passwords.sql` - Empty password audit
- `sql/user/membership.sql` - Role membership tree

### Step 11: Test implementation
- Test with different PostgreSQL versions
- Test with many roles (performance)
- Test with complex role hierarchies
- Test JSON output format
- Test permissions queries on databases with many tables

## Key Files

| File | Operation | Description |
|------|-----------|-------------|
| `commands/user/index.sh` | Create | Command group index |
| `commands/user/list.sh` | Create | User list command |
| `commands/user/info.sh` | Create | User info command |
| `commands/user/permissions.sh` | Create | User permissions command |
| `commands/user/activity.sh` | Create | User activity command |
| `commands/user/audit.sh` | Create | User audit command |
| `commands/user/tree.sh` | Create | User tree command |
| `lib/user.sh` | Create | User utility functions |
| `lib/cli.sh:L15` | Modify | Add "user" to PGTOOL_GROUPS |
| `sql/user/list.sql` | Create | User list SQL |
| `sql/user/info.sql` | Create | User info SQL |
| `sql/user/activity.sql` | Create | Activity SQL |
| `sql/user/permissions_*.sql` | Create | Permission SQLs |
| `sql/user/audit_*.sql` | Create | Audit SQLs |
| `sql/user/membership.sql` | Create | Membership tree SQL |

## Risks and Mitigation

| Risk | Mitigation |
|------|------------|
| Permission queries slow on large databases | Add --limit option, use pagination |
| Role membership cycles | Handle cycles in recursive CTE |
| Sensitive information exposure | Add warning about audit output |
| Version-specific catalog columns | Check PG version in queries |
| Privilege escalation via pgtool | Only use catalog queries, never GRANT/REVOKE |

## Security Considerations

The user command group is **read-only** by design. It will:
- Query system catalogs (pg_roles, pg_auth_members, etc.)
- Show permissions and membership
- Never execute GRANT, REVOKE, CREATE ROLE, DROP ROLE, etc.

Administrators who want to modify users should use:
- `psql` with direct SQL
- `pgtool admin` commands (if admin functions added)

## Pseudo-code

```bash
# lib/user.sh
pgtool_user_build_tree() {
    local root_role="${1:-}"

    # If root_role specified, start from there
    # Otherwise find all root roles (not members of any role)
    # Recursively build tree structure
    # Format with indentation based on level
}

pgtool_user_check_security() {
    local issues=()

    # Check for too many superusers
    local superuser_count
    superuser_count=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_roles WHERE rolsuper")
    if [[ $superuser_count -gt 3 ]]; then
        issues+=("WARNING: Found $superuser_count superusers (recommend max 3)")
    fi

    # Check for empty passwords
    local empty_pass
    empty_pass=$(pgtool_pg_query_one "SELECT COUNT(*) FROM pg_authid WHERE rolpassword IS NULL AND rolcanlogin")
    if [[ $empty_pass -gt 0 ]]; then
        issues+=("CRITICAL: Found $empty_pass roles with empty passwords")
    fi

    printf '%s\n' "${issues[@]}"
}
```

## SESSION_ID
- CODEX_SESSION: N/A (local planning)
- GEMINI_SESSION: N/A (local planning)
