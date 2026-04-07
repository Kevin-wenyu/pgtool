-- sql/stat/sequences.sql
-- 序列统计信息
-- 参数：无
-- 输出：模式、序列名、类型、当前值、最小值、最大值、增量

SELECT
    schemaname AS "模式",
    sequencename AS "序列名",
    data_type AS "类型",
    last_value AS "当前值",
    start_value AS "起始值",
    min_value AS "最小值",
    max_value AS "最大值",
    increment_by AS "增量"
FROM pg_sequences
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, sequencename;
