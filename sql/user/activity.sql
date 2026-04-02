-- User connection activity
-- Parameter: :username (optional, NULL for all)
-- Filter by backend_type = 'client backend'

SELECT
    s.usename AS "User",
    COUNT(*) FILTER (WHERE s.state = 'active') AS "Active",
    COUNT(*) FILTER (WHERE s.state = 'idle') AS "Idle",
    COUNT(*) FILTER (WHERE s.state = 'idle in transaction') AS "Idle in Tx",
    COUNT(*) FILTER (WHERE s.wait_event_type IS NOT NULL) AS "Waiting",
    COUNT(*) AS "Total"
FROM pg_stat_activity s
WHERE s.backend_type = 'client backend'
  AND (:'username' = 'NULL' OR s.usename = :'username')
GROUP BY s.usename
ORDER BY s.usename;
