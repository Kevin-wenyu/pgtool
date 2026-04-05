-- sql/stat/waits.sql
-- 查看数据库等待事件统计
-- 参数：无
-- 输出：等待类型、等待事件、会话数、占比

SELECT
    COALESCE(wait_event_type, 'CPU/Running') AS "Wait Type",
    COALESCE(wait_event, 'N/A') AS "Wait Event",
    COUNT(*) AS "Sessions",
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS "Percentage(%)"
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY wait_event_type, wait_event
ORDER BY COUNT(*) DESC;
