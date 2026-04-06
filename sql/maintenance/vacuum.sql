-- sql/maintenance/vacuum.sql
-- VACUUM 操作 - 清理死亡元组

-- 获取需要vacuum的表
SELECT
    schemaname || '.' || relname as table_name,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 2) as dead_ratio,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    vacuum_count + autovacuum_count as vacuum_count
FROM pg_stat_user_tables
WHERE n_dead_tup > :threshold * 1000
ORDER BY n_dead_tup DESC;
