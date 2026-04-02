-- Database-level permissions
-- Parameter: :username

SELECT
    d.datname AS "Database",
    has_database_privilege(:username, d.datname, 'CONNECT') AS "Connect",
    has_database_privilege(:username, d.datname, 'CREATE') AS "Create",
    has_database_privilege(:username, d.datname, 'TEMPORARY') AS "Temporary"
FROM pg_database d
WHERE d.datallowconn = true
ORDER BY d.datname;
