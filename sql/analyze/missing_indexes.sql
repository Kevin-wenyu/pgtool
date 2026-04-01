-- sql/analyze/missing_indexes.sql
-- 查找可能的缺失索引
-- 参数：无

SELECT
    schemaname || '.' || relname AS "Table",
    seq_scan AS "Seq Scans",
    seq_tup_read AS "Seq Tuples Read",
    idx_scan AS "Idx Scans",
    CASE
        WHEN seq_scan > 0 AND idx_scan > 0
        THEN ROUND(100.0 * seq_scan / (seq_scan + idx_scan), 2)
        WHEN seq_scan > 0 THEN 100.0
        ELSE 0
    END AS "Seq Scan %",
    CASE
        WHEN seq_scan > 100 AND (idx_scan IS NULL OR idx_scan = 0)
            THEN 'MISSING INDEX'
        WHEN seq_scan > idx_scan * 2 AND seq_scan > 100
            THEN 'NEEDS MORE INDEXES'
        ELSE 'OK'
    END AS "Recommendation"
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    AND seq_scan > 50
ORDER BY seq_scan DESC
LIMIT 20;
