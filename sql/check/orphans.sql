-- sql/check/orphans.sql
-- 检查孤儿对象
-- 参数：无
-- 输出：对象类型、模式、对象名、原因、状态

-- 查找孤立的临时表
WITH orphaned_temp_tables AS (
    SELECT
        '临时表' AS object_type,
        schemaname AS schema_name,
        tablename AS object_name,
        '可能来自死连接的临时表' AS reason,
        'INFO' AS status
    FROM pg_stat_user_tables
    WHERE schemaname LIKE 'pg_temp%'
        OR tablename LIKE 'tmp%'
        OR tablename LIKE 'temp%'
),
-- 查找空闲的预提交事务
idle_prepared AS (
    SELECT
        '预提交事务' AS object_type,
        database AS schema_name,
        transaction AS object_name,
        '空闲预提交事务: ' || prepared AS reason,
        CASE
            WHEN prepared < NOW() - INTERVAL '1 hour' THEN 'WARNING'
            ELSE 'OK'
        END AS status
    FROM pg_prepared_xacts
    WHERE prepared < NOW() - INTERVAL '10 minutes'
)
SELECT * FROM orphaned_temp_tables
UNION ALL
SELECT * FROM idle_prepared
ORDER BY status DESC, object_type;
