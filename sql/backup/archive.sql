-- sql/backup/archive.sql
-- WAL archiver status

SELECT
    archived_count AS "Archived",
    failed_count AS "Failed",
    COALESCE(last_archived_time::text, 'N/A') AS "Last Archived",
    COALESCE(last_failed_time::text, 'N/A') AS "Last Failed",
    COALESCE(last_archived_wal, 'N/A') AS "Last WAL",
    CASE
        WHEN failed_count > 0 THEN 'WARNING'
        WHEN last_archived_time < NOW() - INTERVAL '5 minutes' THEN 'WARNING'
        ELSE 'OK'
    END AS "Status"
FROM pg_stat_archiver;
