-- tests/setup_test_data.sql
-- 生成更多测试数据以模拟真实场景

-- 生成慢查询日志数据（pg_stat_statements 需要预先配置）
-- 执行多次复杂查询以产生统计信息
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..100 LOOP
        -- 复杂查询，用于产生统计
        PERFORM COUNT(*) FROM test_orders o
        JOIN test_users u ON o.user_id = u.id
        WHERE o.amount > random() * 500;
    END LOOP;
END $$;

-- 更新表统计信息
VACUUM ANALYZE test_users;
VACUUM ANALYZE test_orders;
VACUUM ANALYZE test_large_table;
