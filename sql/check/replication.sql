-- sql/check/replication.sql
-- 检查流复制状态
-- 参数：无
-- 输出：复制延迟、连接状态等

SELECT
    client_addr AS "Client",
    state AS "State",
    sent_lsn AS "Sent LSN",
    write_lsn AS "Write LSN",
    flush_lsn AS "Flush LSN",
    replay_lsn AS "Replay LSN",
    CASE
        WHEN write_lag IS NULL THEN 'N/A'
        ELSE ROUND(EXTRACT(EPOCH FROM write_lag))::text || 's'
    END AS "Write Lag",
    CASE
        WHEN flush_lag IS NULL THEN 'N/A'
        ELSE ROUND(EXTRACT(EPOCH FROM flush_lag))::text || 's'
    END AS "Flush Lag",
    CASE
        WHEN replay_lag IS NULL THEN 'N/A'
        ELSE ROUND(EXTRACT(EPOCH FROM replay_lag))::text || 's'
    END AS "Replay Lag"
FROM pg_stat_replication
ORDER BY client_addr;
