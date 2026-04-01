-- sql/stat/index.sql
-- 查看索引使用情况
-- 参数：无

SELECT
    schemaname || '.' || relname AS "Table",
    indexrelname AS "Index",
    pg_size_pretty(pg_relation_size(indexrelid)) AS "Index Size",
    idx_scan AS "Index Scans",
    idx_tup_read AS "Tuples Read",
    idx_tup_fetch AS "Tuples Fetched",
    CASE
        WHEN idx_scan = 0 THEN 'UNUSED'
        WHEN idx_scan < 10 THEN 'LOW'
        ELSE 'OK'
    END AS "Usage"
FROM pg_stat_user_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 30;
