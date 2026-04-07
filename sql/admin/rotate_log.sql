-- sql/admin/rotate_log.sql
-- 轮换PostgreSQL日志文件
-- 参数：无
-- 输出：状态

SELECT pg_rotate_logfile() AS "日志轮换状态";
