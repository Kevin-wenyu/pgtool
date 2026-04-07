-- Check for sequences approaching exhaustion
-- Parameters: warning_threshold (default 80), critical_threshold (default 95)
-- Output: schema, sequence_name, type, current, min, max, usage_pct, status

WITH sequence_stats AS (
    SELECT
        schemaname AS schema,
        sequencename AS sequence_name,
        last_value AS current_value,
        -- Get sequence data type and limits
        CASE
            WHEN seqtypid = 'bigint'::regtype THEN 9223372036854775807::bigint
            WHEN seqtypid = 'integer'::regtype THEN 2147483647::integer
            WHEN seqtypid = 'smallint'::regtype THEN 32767::smallint
            ELSE 2147483647::bigint  -- Default to integer max
        END AS max_value,
        seqtypid::regtype AS data_type
    FROM pg_sequences ps
    JOIN pg_class c ON c.relname = ps.sequencename
    JOIN pg_sequence s ON s.seqrelid = c.oid
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
),
sequence_usage AS (
    SELECT
        schema,
        sequence_name,
        data_type,
        current_value,
        max_value,
        CASE
            WHEN max_value > 0 THEN
                ROUND((current_value::numeric / max_value::numeric) * 100, 2)
            ELSE 0
        END AS usage_pct
    FROM sequence_stats
    WHERE current_value IS NOT NULL
)
SELECT
    schema,
    sequence_name,
    data_type,
    current_value,
    max_value,
    usage_pct,
    CASE
        WHEN usage_pct >= 95 THEN 'CRITICAL'
        WHEN usage_pct >= 80 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM sequence_usage
ORDER BY usage_pct DESC;
