-- sql/admin/cancel_query.sql
-- 取消指定 PID 的查询
-- 参数：pid

-- 查询信息
SELECT
    pid,
    usename,
    datname,
    state,
    EXTRACT(EPOCH FROM (now() - query_start))::int AS duration_seconds,
    query
FROM pg_stat_activity
WHERE pid = :pid;
