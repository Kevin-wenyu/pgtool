-- sql/maintenance/reindex.sql
-- 检查膨胀索引

SELECT
    schemaname || '.' || indexrelname as index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    pg_size_pretty(pg_relation_size(relid)) as table_size,
    round(pg_relation_size(indexrelid)::numeric / nullif(pg_relation_size(relid), 0), 2) as size_ratio,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid) - pg_relation_size(relid) * 0.3) as estimated_bloat
FROM pg_stat_user_indexes
WHERE pg_relation_size(indexrelid) > pg_relation_size(relid) * :min_ratio
ORDER BY pg_relation_size(indexrelid) DESC;
