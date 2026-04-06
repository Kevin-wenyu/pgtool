-- sql/check/invalid_indexes.sql
-- 检查无效索引

SELECT
    schemaname || '.' || indexrelname as index_name,
    schemaname || '.' || relname as table_name,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    'INVALID' as status,
    '索引已失效，需要重建' as recommendation
FROM pg_stat_user_indexes sui
JOIN pg_index pi ON sui.indexrelid = pi.indexrelid
WHERE NOT pi.indisvalid
ORDER BY pg_relation_size(indexrelid) DESC;
