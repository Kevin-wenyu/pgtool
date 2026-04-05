-- sql/check/long_tx.sql
-- 检查长事务
-- 参数：阈值(分钟，默认5)

SELECT
    pid AS "PID",
    usename AS "User",
    datname AS "Database",
    state AS "State",
    EXTRACT(EPOCH FROM (now() - xact_start))::int / 60 AS "Tx Duration(min)",
    EXTRACT(EPOCH FROM (now() - query_start))::int / 60 AS "Query Duration(min)",
    LEFT(query, 80) AS "Query"
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND pid != pg_backend_pid()
  AND EXTRACT(EPOCH FROM (now() - xact_start)) > :threshold * 60
ORDER BY xact_start ASC;
