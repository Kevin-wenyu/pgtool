-- sql/stat/table.sql
-- 查看表级统计
-- 参数：可选 schema 名

SELECT
    schemaname || '.' || relname AS "Table",
    pg_size_pretty(pg_total_relation_size(relid)) AS "Total Size",
    pg_size_pretty(pg_relation_size(relid)) AS "Table Size",
    pg_size_pretty(pg_indexes_size(relid)) AS "Index Size",
    seq_scan AS "Seq Scans",
    seq_tup_read AS "Seq Tuples",
    idx_scan AS "Idx Scans",
    idx_tup_fetch AS "Idx Tuples",
    n_tup_ins AS "Inserts",
    n_tup_upd AS "Updates",
    n_tup_del AS "Deletes",
    n_tup_hot_upd AS "Hot Updates",
    n_live_tup AS "Live Tuples",
    n_dead_tup AS "Dead Tuples",
    CASE
        WHEN n_live_tup + n_dead_tup > 0
        THEN ROUND(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
        ELSE 0
    END AS "Dead Ratio %",
    last_vacuum AS "Last Vacuum",
    last_autovacuum AS "Last AutoVacuum",
    last_analyze AS "Last Analyze",
    vacuum_count AS "Vacuum Count"
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 20;
