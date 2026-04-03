SELECT datname, state, COUNT(*) AS count,
       COALESCE(SUM(EXTRACT(EPOCH FROM (now() - backend_start)))::bigint / COUNT(*), 0) AS avg_conn_time
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY datname, state
ORDER BY count DESC, datname;
