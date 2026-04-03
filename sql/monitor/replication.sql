SELECT client_addr AS replica, state, sent_lsn::text, flush_lsn::text,
       pg_wal_lsn_diff(sent_lsn, flush_lsn) AS lag_bytes,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, flush_lsn)) AS lag_size,
       reply_time
FROM pg_stat_replication
ORDER BY lag_bytes DESC;
