-- sql/maintenance/analyze.sql
-- 检查需要ANALYZE的表

SELECT
    schemaname || '.' || relname as table_name,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    last_analyze,
    last_autoanalyze,
    round(EXTRACT(EPOCH FROM (now() - GREATEST(last_analyze, last_autoanalyze))) / 3600, 1) as hours_since_analyze,
    analyze_count + autoanalyze_count as analyze_count,
    CASE
        WHEN n_live_tup > 10000 AND last_analyze IS NULL THEN 'NEEDED'
        WHEN EXTRACT(EPOCH FROM (now() - GREATEST(last_analyze, last_autoanalyze))) > :hours * 3600 THEN 'STALE'
        ELSE 'OK'
    END as status
FROM pg_stat_user_tables
WHERE n_live_tup > 0
ORDER BY EXTRACT(EPOCH FROM (now() - GREATEST(last_analyze, last_autoanalyze))) DESC NULLS FIRST;
