-- sql/stat/activity.sql
-- 查看活动会话
-- 参数：无
-- 输出：pid, usename, datname, state, query_start, query

SELECT
    pid AS "PID",
    usename AS "User",
    datname AS "Database",
    COALESCE(client_addr::text, 'local') AS "Client",
    state AS "State",
    CASE
        WHEN state = 'active' THEN EXTRACT(EPOCH FROM (now() - query_start))::int
        ELSE EXTRACT(EPOCH FROM (now() - state_change))::int
    END AS "Duration(s)",
    LEFT(query, 60) AS "Query"
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
ORDER BY
    CASE state
        WHEN 'active' THEN 0
        WHEN 'idle in transaction' THEN 1
        WHEN 'idle' THEN 2
        ELSE 3
    END,
    COALESCE(query_start, state_change) DESC;
