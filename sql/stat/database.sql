-- sql/stat/database.sql
-- 查看数据库级统计
-- 参数：无

SELECT
    datname AS "Database",
    pg_size_pretty(pg_database_size(datname)) AS "Size",
    numbackends AS "Connections",
    xact_commit AS "Commits",
    xact_rollback AS "Rollbacks",
    ROUND(100.0 * xact_rollback / NULLIF(xact_commit + xact_rollback, 0), 2) AS "Rollback %",
    blks_read AS "Blocks Read",
    blks_hit AS "Blocks Hit",
    ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS "Cache Hit %",
    tup_returned AS "Tuples Read",
    tup_fetched AS "Tuples Fetched",
    tup_inserted AS "Tuples Inserted",
    tup_updated AS "Tuples Updated",
    tup_deleted AS "Tuples Deleted",
    conflicts AS "Conflicts",
    temp_files AS "Temp Files",
    pg_size_pretty(temp_bytes) AS "Temp Bytes",
    pg_size_pretty(deadlocks) AS "Deadlocks"
FROM pg_stat_database
WHERE datname IN (SELECT datname FROM pg_database WHERE datallowconn)
ORDER BY pg_database_size(datname) DESC;
