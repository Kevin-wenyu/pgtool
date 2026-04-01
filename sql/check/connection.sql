-- sql/check/connection.sql
-- 检查连接数使用情况
-- 参数：无

SELECT
    current_setting('max_connections')::int AS "Max Connections",
    (SELECT COUNT(*) FROM pg_stat_activity) AS "Current Connections",
    (SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active') AS "Active",
    (SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'idle') AS "Idle",
    (SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'idle in transaction') AS "Idle in Transaction",
    (SELECT COUNT(*) FROM pg_stat_activity WHERE wait_event IS NOT NULL) AS "Waiting",
    ROUND((SELECT COUNT(*)::numeric * 100 / NULLIF(current_setting('max_connections')::int, 0)
           FROM pg_stat_activity), 2) AS "Usage %";
