-- Detailed user information for a specific user
-- Parameter: :username

SELECT
    r.rolname AS "User",
    r.rolsuper AS "Superuser",
    r.rolinherit AS "Inherit",
    r.rolcreaterole AS "Create Role",
    r.rolcreatedb AS "Create DB",
    r.rolcanlogin AS "Can Login",
    r.rolconnlimit AS "Conn Limit",
    COALESCE(r.rolvaliduntil::text, 'Never') AS "Password Expires",
    r.rolreplication AS "Replication",
    r.rolbypassrls AS "Bypass RLS",
    COALESCE(
        (SELECT string_agg(g.rolname, ', ' ORDER BY g.rolname)
         FROM pg_auth_members m
         JOIN pg_roles g ON m.roleid = g.oid
         WHERE m.member = r.oid),
        ''
    ) AS "Member Of",
    COALESCE(
        (SELECT string_agg(m.rolname, ', ' ORDER BY m.rolname)
         FROM pg_auth_members am
         JOIN pg_roles m ON am.member = m.oid
         WHERE am.roleid = r.oid),
        ''
    ) AS "Has Members"
FROM pg_roles r
WHERE r.rolname = :username;
