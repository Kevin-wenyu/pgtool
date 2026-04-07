-- sql/analyze/index_usage.sql
-- 分析索引使用情况
-- 参数：无

SELECT
    schemaname AS "Schema",
    relname AS "Table",
    indexrelname AS "Index",
    idx_scan AS "Scans",
    pg_size_pretty(pg_relation_size(indexrelid)) AS "Size",
    CASE
        WHEN idx_scan = 0 THEN 'UNUSED'
        WHEN idx_scan < 10 THEN 'RARELY USED'
        ELSE 'ACTIVE'
    END AS "Status"
FROM pg_stat_user_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC
LIMIT 50;
