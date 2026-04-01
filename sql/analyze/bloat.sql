-- sql/analyze/bloat.sql
-- 分析表和索引膨胀
-- 参数：无

-- 表膨胀分析
SELECT
    schemaname || '.' || relname AS "Table",
    pg_size_pretty(pg_total_relation_size(relid)) AS "Total Size",
    n_live_tup AS "Live Tuples",
    n_dead_tup AS "Dead Tuples",
    CASE
        WHEN n_live_tup + n_dead_tup > 0
        THEN ROUND(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
        ELSE 0
    END AS "Dead Ratio %",
    CASE
        WHEN n_dead_tup > n_live_tup * 0.2 THEN 'HIGH'
        WHEN n_dead_tup > n_live_tup * 0.1 THEN 'MEDIUM'
        ELSE 'OK'
    END AS "Bloat Level",
    last_vacuum AS "Last Vacuum",
    last_autovacuum AS "Last AutoVacuum"
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    AND n_dead_tup > 1000
ORDER BY n_dead_tup DESC
LIMIT 20;
