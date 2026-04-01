-- sql/check/xid.sql
-- 检查数据库 XID 年龄
-- 参数：无
-- 输出：datname, age, warning_level

SELECT
    datname AS "Database",
    age(datfrozenxid) AS "XID Age",
    CASE
        WHEN age(datfrozenxid) > 2000000000 THEN 'CRITICAL'
        WHEN age(datfrozenxid) > 1500000000 THEN 'WARNING'
        ELSE 'OK'
    END AS "Status"
FROM pg_database
WHERE datallowconn
ORDER BY age(datfrozenxid) DESC;
