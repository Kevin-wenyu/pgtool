-- Parameters: :limit
SELECT pid, usename, datname, client_addr::text, state,
       COALESCE(EXTRACT(EPOCH FROM (now() - query_start))::int, 0) AS query_time,
       LEFT(query, 100) AS query_text
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
  AND backend_type = 'client backend'
ORDER BY query_start DESC NULLS LAST
LIMIT :limit;
