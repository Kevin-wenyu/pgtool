-- sql/check/cache_hit.sql
-- 检查数据库缓存命中率
-- 参数：阈值警告(默认95%), 阈值危险(默认90%)

WITH cache_stats AS (
    SELECT
        datname,
        blks_hit,
        blks_read,
        CASE WHEN blks_hit + blks_read > 0
            THEN ROUND(100.0 * blks_hit / (blks_hit + blks_read), 2)
            ELSE 100.0
        END AS hit_ratio
    FROM pg_stat_database
    WHERE datname IS NOT NULL
)
SELECT
    datname AS "Database",
    blks_hit AS "Blocks Hit",
    blks_read AS "Blocks Read",
    hit_ratio AS "Hit Ratio(%)",
    CASE
        WHEN hit_ratio < 90 THEN 'CRITICAL'
        WHEN hit_ratio < 95 THEN 'WARNING'
        ELSE 'OK'
    END AS "Status"
FROM cache_stats
ORDER BY hit_ratio ASC;
