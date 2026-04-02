-- List all database users with role attributes
-- Filter out system roles (pg_*, rds_superuser)
-- Order by superuser desc, then name

SELECT
    r.rolname AS "User",
    r.rolsuper AS "Superuser",
    r.rolcreatedb AS "Create DB",
    r.rolcreaterole AS "Create Role",
    r.rolcanlogin AS "Can Login",
    r.rolconnlimit AS "Conn Limit",
    COALESCE(r.rolvaliduntil::text, 'Never') AS "Password Expires",
    COALESCE(
        (SELECT string_agg(g.rolname, ', ' ORDER BY g.rolname)
         FROM pg_auth_members m
         JOIN pg_roles g ON m.roleid = g.oid
         WHERE m.member = r.oid),
        ''
    ) AS "Member Of"
FROM pg_roles r
WHERE r.rolname NOT LIKE 'pg_%'
  AND r.rolname NOT IN ('rds_superuser')
ORDER BY r.rolsuper DESC, r.rolname;
