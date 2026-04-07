-- sql/stat/functions.sql
-- 函数调用统计
-- 参数：无
-- 输出：模式、函数名、调用次数、总时间、平均时间

SELECT
    schemaname AS "模式",
    funcname AS "函数名",
    calls AS "调用次数",
    ROUND(total_exec_time::numeric, 3) AS "总时间(ms)",
    ROUND(mean_exec_time::numeric, 3) AS "平均时间(ms)"
FROM pg_stat_user_functions
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY total_exec_time DESC
LIMIT 100;
