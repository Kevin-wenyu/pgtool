-- sql/analyze/slow_queries.sql
-- 分析慢查询（基于 pg_stat_statements，如果已安装）
-- 参数：无

-- 检查 pg_stat_statements 是否安装
SELECT
    'pg_stat_statements not installed' AS "Status"
WHERE NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'
)

UNION ALL

-- 如果已安装，显示慢查询
SELECT
    query AS "Query",
    calls AS "Calls",
    ROUND(total_exec_time::numeric, 2) AS "Total Time (ms)",
    ROUND(mean_exec_time::numeric, 2) AS "Mean Time (ms)",
    ROUND(max_exec_time::numeric, 2) AS "Max Time (ms)",
    rows AS "Rows",
    ROUND(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) AS "Cache Hit %"
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
