-- sql/analyze/vacuum_stats.sql
-- 查看 vacuum 统计信息
-- 参数：无

SELECT
    schemaname || '.' || relname AS "Table",
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
    last_autoanalyze AS "Last AutoAnalyze",
    vacuum_count AS "Vacuum Count",
    autovacuum_count AS "AutoVacuum Count",
    analyze_count AS "Analyze Count",
    autoanalyze_count AS "AutoAnalyze Count"
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n_dead_tup DESC
LIMIT 20;
