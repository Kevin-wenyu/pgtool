-- sql/config/validate.sql
-- 验证 PostgreSQL 配置参数是否符合最佳实践
-- 参数：无
-- 输出：parameter, current_value, recommended, status

WITH params AS (
    SELECT name, setting, unit,
           CASE
               WHEN vartype = 'integer' OR vartype = 'real' THEN
                   setting::numeric
               ELSE NULL
           END AS numeric_value
    FROM pg_settings
    WHERE name IN ('max_connections', 'shared_buffers', 'work_mem',
                   'autovacuum', 'logging_collector', 'track_activities')
),
recommendations AS (
    SELECT 'max_connections' AS param,
           '<= 100' AS recommended_range,
           100 AS max_val,
           NULL AS min_val,
           'shared_buffers' AS related_param
    UNION ALL
    SELECT 'shared_buffers',
           '25% of RAM or 8GB',
           NULL,
           134217728,  -- 128MB in bytes
           NULL
    UNION ALL
    SELECT 'work_mem',
           '10MB - 64MB',
           65536,  -- 64MB in KB
           10240,  -- 10MB in KB
           'max_connections'
    UNION ALL
    SELECT 'autovacuum',
           'on',
           NULL,
           NULL,
           NULL
    UNION ALL
    SELECT 'logging_collector',
           'on',
           NULL,
           NULL,
           NULL
    UNION ALL
    SELECT 'track_activities',
           'on',
           NULL,
           NULL,
           NULL
)
SELECT
    p.name AS "parameter",
    CASE
        WHEN p.unit IS NOT NULL THEN p.setting || ' (' || p.unit || ')'
        ELSE p.setting
    END AS "current_value",
    r.recommended_range AS "recommended",
    CASE
        WHEN p.name IN ('autovacuum', 'logging_collector', 'track_activities') THEN
            CASE
                WHEN LOWER(p.setting) = 'on' THEN 'OK'
                ELSE 'WARNING'
            END
        WHEN p.name = 'max_connections' THEN
            CASE
                WHEN p.numeric_value > 100 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN p.name = 'shared_buffers' THEN
            CASE
                WHEN p.numeric_value < 131072 THEN 'WARNING'  -- less than 128MB
                ELSE 'OK'
            END
        WHEN p.name = 'work_mem' THEN
            CASE
                WHEN p.numeric_value < 4096 THEN 'CRITICAL'  -- less than 4MB
                WHEN p.numeric_value < 8192 THEN 'WARNING'   -- less than 8MB
                ELSE 'OK'
            END
        ELSE 'OK'
    END AS "status"
FROM params p
JOIN recommendations r ON p.name = r.param
ORDER BY
    CASE p.name
        WHEN 'max_connections' THEN 1
        WHEN 'shared_buffers' THEN 2
        WHEN 'work_mem' THEN 3
        WHEN 'autovacuum' THEN 4
        WHEN 'logging_collector' THEN 5
        WHEN 'track_activities' THEN 6
    END;
