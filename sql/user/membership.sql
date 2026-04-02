-- Role membership tree (recursive CTE)
-- Parameter: :role (optional, NULL for all roots)

WITH RECURSIVE role_tree AS (
    -- Base case: start with root roles
    SELECT
        r.oid AS role_oid,
        r.rolname AS role_name,
        NULL::name AS member_of,
        0 AS depth
    FROM pg_roles r
    WHERE r.rolname NOT LIKE 'pg_%'
      AND r.rolname NOT IN ('rds_superuser')
      AND NOT EXISTS (
          SELECT 1 FROM pg_auth_members m
          JOIN pg_roles p ON m.roleid = p.oid
          WHERE m.member = r.oid
            AND p.rolname NOT LIKE 'pg_%'
            AND p.rolname NOT IN ('rds_superuser')
      )
      AND (:role IS NULL OR r.rolname = :role)

    UNION ALL

    -- Recursive case: find members of each role
    SELECT
        m.member AS role_oid,
        r.rolname AS role_name,
        rt.role_name AS member_of,
        rt.depth + 1 AS depth
    FROM role_tree rt
    JOIN pg_auth_members m ON rt.role_oid = m.roleid
    JOIN pg_roles r ON m.member = r.oid
    WHERE r.rolname NOT LIKE 'pg_%'
      AND r.rolname NOT IN ('rds_superuser')
)
SELECT
    role_name AS "Role",
    COALESCE(member_of::text, '') AS "Member Of",
    depth AS "Depth"
FROM role_tree
ORDER BY depth, member_of NULLS FIRST, role_name;
