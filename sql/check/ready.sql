-- sql/check/ready.sql
-- 检查数据库是否就绪（可接受连接）

WITH readiness_check AS (
    SELECT
        pg_is_in_recovery() as in_recovery,
        pg_current_wal_lsn() as current_lsn,
        current_setting('max_connections') as max_conn,
        (SELECT count(*) FROM pg_stat_activity) as current_conn
)
SELECT
    CASE
        WHEN in_recovery AND :accept_standby = 0 THEN 'STANDBY'
        ELSE 'READY'
    END as status,
    CASE
        WHEN in_recovery THEN '数据库处于恢复模式（备库）'
        ELSE '数据库正常运行'
    END as description,
    max_conn as max_connections,
    current_conn as current_connections,
    round(current_conn::numeric / max_conn::numeric * 100, 2) as connection_usage_pct
FROM readiness_check;
