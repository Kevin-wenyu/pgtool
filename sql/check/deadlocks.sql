-- sql/check/deadlocks.sql
-- 检查死锁

-- 获取死锁统计
SELECT
    datname as database,
    deadlocks,
    stats_reset,
    CASE
        WHEN deadlocks > :threshold THEN 'WARNING'
        ELSE 'OK'
    END as status,
    CASE
        WHEN deadlocks > 0 THEN '自上次统计重置以来发生' || deadlocks || '次死锁'
        ELSE '未检测到死锁'
    END as description
FROM pg_stat_database
WHERE datname = current_database()
ORDER BY deadlocks DESC;
