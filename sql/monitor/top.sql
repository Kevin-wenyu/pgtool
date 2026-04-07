-- Parameters: :limit
-- Real-time activity monitoring (top-like view)
SELECT
    pid,
    usename AS user,
    datname AS database,
    state,
    COALESCE(EXTRACT(EPOCH FROM (now() - query_start))::numeric(10,2), 0) AS duration,
    LEFT(query, 60) AS query
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
  AND backend_type = 'client backend'
ORDER BY duration DESC
LIMIT :limit;
