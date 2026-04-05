-- sql/check/tablespace.sql
-- 检查表空间使用情况
-- 参数：无
-- 输出：表空间名、大小、位置

SELECT
    spcname AS "Tablespace",
    pg_size_pretty(pg_tablespace_size(spcname)) AS "Size",
    COALESCE(pg_tablespace_location(oid), '(default)') AS "Location"
FROM pg_tablespace
ORDER BY pg_tablespace_size(spcname) DESC;
