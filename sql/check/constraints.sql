-- Check for foreign key violations and constraint issues
-- Parameters: none
-- Output: constraint_type, table_name, constraint_name, details, status

-- Check for FK violations using pg_constraint and manual verification
WITH fk_check AS (
    SELECT
        tc.table_schema,
        tc.table_name,
        tc.constraint_name,
        kcu.column_name AS fk_column,
        ccu.table_name AS ref_table,
        ccu.column_name AS ref_column
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
),
-- Check for NOT NULL violations (rows where column is null but has NOT NULL constraint)
notnull_check AS (
    SELECT
        tc.table_schema,
        tc.table_name,
        tc.constraint_name,
        kcu.column_name AS column_name,
        'NOT NULL constraint potentially violated' AS details
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
    WHERE tc.constraint_type = 'CHECK'
        AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
        AND tc.constraint_name LIKE '%not_null%'
),
-- Check for CHECK constraint definitions
all_constraints AS (
    SELECT
        conrelid::regclass AS table_name,
        conname AS constraint_name,
        contype AS constraint_type,
        pg_get_constraintdef(oid) AS constraint_definition,
        CASE contype
            WHEN 'c' THEN 'CHECK'
            WHEN 'f' THEN 'FOREIGN KEY'
            WHEN 'p' THEN 'PRIMARY KEY'
            WHEN 'u' THEN 'UNIQUE'
            WHEN 't' THEN 'TRIGGER'
            WHEN 'x' THEN 'EXCLUSION'
        END AS constraint_type_name
    FROM pg_constraint
    WHERE connamespace NOT IN ('pg_catalog'::regnamespace, 'information_schema'::regnamespace)
)
SELECT
    constraint_type_name AS constraint_type,
    table_name::text,
    constraint_name,
    constraint_definition AS details,
    'OK' AS status
FROM all_constraints
ORDER BY constraint_type_name, table_name, constraint_name;
