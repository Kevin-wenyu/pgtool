-- sql/check/sequences.sql
-- 检查序列使用情况
-- 参数：无

WITH sequence_stats AS (
    SELECT
        schemaname AS "模式",
        sequencename AS "序列名",
        last_value AS "当前值",
        -- Get sequence data type and limits from pg_sequence
        CASE
            WHEN seqtypid = 'bigint'::regtype THEN 9223372036854775807::bigint
            WHEN seqtypid = 'integer'::regtype THEN 2147483647::integer
            WHEN seqtypid = 'smallint'::regtype THEN 32767::smallint
            ELSE 2147483647::bigint  -- Default to integer max
        END AS max_value,
        seqtypid::regtype AS "数据类型",
        seqstart AS start_value,
        seqincrement AS increment_by
    FROM pg_sequences ps
    JOIN pg_class c ON c.oid = (quote_ident(ps.schemaname) || '.' || quote_ident(ps.sequencename))::regclass
    JOIN pg_sequence s ON s.seqrelid = c.oid
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
),
sequence_usage AS (
    SELECT
        "模式",
        "序列名",
        "数据类型",
        "当前值",
        max_value,
        start_value,
        increment_by,
        CASE
            WHEN increment_by > 0 THEN
                -- For positive increment: usage = (current - start) / (max - start)
                CASE
                    WHEN max_value > start_value THEN
                        ROUND((("当前值"::numeric - start_value::numeric) / (max_value::numeric - start_value::numeric)) * 100, 2)
                    ELSE 0
                END
            WHEN increment_by < 0 THEN
                -- For negative increment: sequences count down
                -- Min value for signed types: -9223372036854775808 for bigint, -2147483648 for int, -32768 for smallint
                CASE
                    WHEN "数据类型" = 'bigint' THEN
                        ROUND((("当前值"::numeric - (-9223372036854775808::numeric)) / (start_value::numeric - (-9223372036854775808::numeric))) * 100, 2)
                    WHEN "数据类型" = 'integer' THEN
                        ROUND((("当前值"::numeric - (-2147483648::numeric)) / (start_value::numeric - (-2147483648::numeric))) * 100, 2)
                    WHEN "数据类型" = 'smallint' THEN
                        ROUND((("当前值"::numeric - (-32768::numeric)) / (start_value::numeric - (-32768::numeric))) * 100, 2)
                    ELSE 0
                END
            ELSE 0
        END AS "使用率%"
    FROM sequence_stats
    WHERE "当前值" IS NOT NULL
)
SELECT
    "模式",
    "序列名",
    "数据类型",
    "当前值",
    max_value AS "最大值",
    start_value AS "起始值",
    increment_by AS "增量",
    "使用率%",
    CASE
        WHEN "使用率%" >= 95 THEN 'CRITICAL'
        WHEN "使用率%" >= 80 THEN 'WARNING'
        ELSE 'OK'
    END AS "状态"
FROM sequence_usage
ORDER BY "使用率%" DESC;
