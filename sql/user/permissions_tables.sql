-- Table-level permissions
-- Parameters: :username, :limit

SELECT
    n.nspname AS "Schema",
    c.relname AS "Table",
    pg_catalog.has_any_column_privilege(:username, c.oid, 'SELECT') OR
    pg_catalog.has_table_privilege(:username, c.oid, 'SELECT') AS "Select",
    pg_catalog.has_any_column_privilege(:username, c.oid, 'INSERT') OR
    pg_catalog.has_table_privilege(:username, c.oid, 'INSERT') AS "Insert",
    pg_catalog.has_any_column_privilege(:username, c.oid, 'UPDATE') OR
    pg_catalog.has_table_privilege(:username, c.oid, 'UPDATE') AS "Update",
    pg_catalog.has_any_column_privilege(:username, c.oid, 'DELETE') OR
    pg_catalog.has_table_privilege(:username, c.oid, 'DELETE') AS "Delete",
    pg_catalog.has_table_privilege(:username, c.oid, 'TRUNCATE') AS "Truncate",
    pg_catalog.has_table_privilege(:username, c.oid, 'REFERENCES') AS "References",
    pg_catalog.has_table_privilege(:username, c.oid, 'TRIGGER') AS "Trigger"
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'v', 'm')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND pg_catalog.has_any_column_privilege(:username, c.oid, 'SELECT, INSERT, UPDATE, DELETE')
     OR pg_catalog.has_table_privilege(:username, c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
ORDER BY n.nspname, c.relname
LIMIT :limit;
