-- sql/check/constraints.sql
-- 列出数据库中的所有约束
-- 参数：无
-- 输出：模式、表名、约束名、约束类型、定义

SELECT
    n.nspname AS "模式",
    c.relname AS "表名",
    con.conname AS "约束名",
    CASE con.contype
        WHEN 'c' THEN 'CHECK'
        WHEN 'f' THEN '外键'
        WHEN 'p' THEN '主键'
        WHEN 'u' THEN '唯一约束'
        WHEN 't' THEN '触发器'
        WHEN 'x' THEN '排他约束'
    END AS "约束类型",
    pg_get_constraintdef(con.oid) AS "定义"
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = con.connamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, c.relname,
    CASE con.contype
        WHEN 'p' THEN 1
        WHEN 'u' THEN 2
        WHEN 'f' THEN 3
        WHEN 'c' THEN 4
        WHEN 'x' THEN 5
        WHEN 't' THEN 6
    END, con.conname;
