-- sql/check/replication_lag.sql
-- 检查复制延迟
-- 在主库查询：显示从库的延迟
-- 在从库查询：显示接收和应用延迟

-- 主库视角：查看连接的从库延迟
SELECT
    client_addr AS "Standby",
    state AS "State",
    sent_lsn - replay_lsn AS "Lag(bytes)",
    EXTRACT(EPOCH FROM (now() - backend_start))::int / 60 AS "Connected(min)",
    sync_state AS "Sync Mode"
FROM pg_stat_replication
ORDER BY sent_lsn - replay_lsn DESC;
