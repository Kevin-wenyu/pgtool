-- sql/admin/kill_blocking.sql
-- 查找并终止阻塞其他会话的进程
-- 参数：可选指定 PID

SELECT
    pid,
    usename,
    datname,
    state,
    EXTRACT(EPOCH FROM (now() - query_start))::int AS duration_seconds,
    LEFT(query, 100) AS query_snippet
FROM pg_stat_activity
WHERE pid IN (
    SELECT DISTINCT blocking_locks.pid
    FROM pg_locks blocking_locks
    JOIN pg_locks waiting_locks
        ON blocking_locks.locktype = waiting_locks.locktype
        AND blocking_locks.relation = waiting_locks.relation
        AND blocking_locks.page = waiting_locks.page
        AND blocking_locks.tuple = waiting_locks.tuple
    JOIN pg_stat_activity waiting_activity
        ON waiting_locks.pid = waiting_activity.pid
    WHERE NOT waiting_locks.granted
        AND blocking_locks.granted
        AND waiting_activity.wait_event IS NOT NULL
)
ORDER BY EXTRACT(EPOCH FROM (now() - query_start)) DESC;
