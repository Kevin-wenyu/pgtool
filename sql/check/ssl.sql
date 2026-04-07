-- sql/check/ssl.sql
-- 检查SSL/TLS配置
-- 参数：无
-- 输出：检查项、当前值、建议值、状态

WITH ssl_config AS (
    SELECT
        'SSL Enabled' AS "检查项",
        current_setting('ssl') AS "当前值",
        'on' AS "建议值",
        CASE WHEN current_setting('ssl') = 'on' THEN 'OK' ELSE 'WARNING' END AS "状态"
    UNION ALL
    SELECT
        'SSL证书文件',
        COALESCE(NULLIF(current_setting('ssl_cert_file'), ''), '未配置'),
        '已配置',
        CASE WHEN current_setting('ssl_cert_file') = '' THEN 'WARNING' ELSE 'OK' END
    UNION ALL
    SELECT
        '连接SSL状态',
        ssl::text,
        'true',
        CASE WHEN ssl THEN 'OK' ELSE 'WARNING' END
    FROM pg_stat_ssl WHERE pid = pg_backend_pid()
)
SELECT * FROM ssl_config;
