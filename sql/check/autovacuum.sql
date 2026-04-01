-- sql/check/autovacuum.sql
-- 检查 autovacuum 状态
-- 参数：无

-- 正在运行的 autovacuum 进程
SELECT
    'Running Autovacuum' AS "Category",
    COUNT(*)::text AS "Count"
FROM pg_stat_activity
WHERE query LIKE 'autovacuum: %'

UNION ALL

-- 需要 vacuum 的表（超过 autovacuum 阈值）
SELECT
    'Tables Needing Vacuum' AS "Category",
    COUNT(*)::text AS "Count"
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
    AND n_live_tup > 0
    AND (n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0)) > 0.1

UNION ALL

-- 长期未 vacuum 的表（超过 1 天）
SELECT
    'Tables Not Vacuumed (24h)' AS "Category",
    COUNT(*)::text AS "Count"
FROM pg_stat_user_tables
WHERE (last_vacuum IS NULL OR last_vacuum < now() - interval '1 day')
    AND (last_autovacuum IS NULL OR last_autovacuum < now() - interval '1 day')

ORDER BY "Category";
