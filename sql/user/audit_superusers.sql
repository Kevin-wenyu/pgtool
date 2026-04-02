-- List superusers for security audit
-- Exclude built-in postgres/rds_superuser from custom count

SELECT
    r.rolname AS "User",
    CASE
        WHEN r.rolname IN ('postgres') THEN 'Built-in'
        ELSE 'Custom'
    END AS "Type",
    r.rolcreaterole AS "Can Create Roles",
    r.rolcanlogin AS "Can Login"
FROM pg_roles r
WHERE r.rolsuper = true
  AND r.rolname NOT LIKE 'pg_%'
  AND r.rolname NOT IN ('rds_superuser')
ORDER BY
    CASE WHEN r.rolname = 'postgres' THEN 0 ELSE 1 END,
    r.rolname;
