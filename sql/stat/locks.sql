-- sql/stat/locks.sql
-- 查看锁等待
-- 参数：无
-- 输出：等待进程、阻塞进程、等待对象、等待时间

SELECT
    w.pid AS "Wait PID",
    w.usename AS "Wait User",
    w.datname AS "Database",
    b.pid AS "Block PID",
    b.usename AS "Block User",
    COALESCE(l.relation::regclass::text, l.locktype) AS "Object",
    l.mode AS "Wait Mode",
    EXTRACT(EPOCH FROM (now() - w.query_start))::int AS "Wait(s)",
    LEFT(w.query, 40) AS "Wait Query",
    LEFT(b.query, 40) AS "Block Query"
FROM pg_stat_activity w
JOIN pg_locks l ON w.pid = l.pid AND NOT l.granted
JOIN pg_locks l2 ON l.locktype = l2.locktype
    AND l.relation = l2.relation
    AND l.page = l2.page
    AND l.tuple = l2.tuple
    AND l2.granted
JOIN pg_stat_activity b ON l2.pid = b.pid
WHERE w.wait_event IS NOT NULL
ORDER BY w.query_start;
