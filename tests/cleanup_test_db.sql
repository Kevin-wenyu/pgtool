-- tests/cleanup_test_db.sql
-- 清理测试数据

DROP TABLE IF EXISTS test_orders CASCADE;
DROP TABLE IF EXISTS test_users CASCADE;
DROP TABLE IF EXISTS test_large_table CASCADE;
DROP FUNCTION IF EXISTS pgtool_test_slow_query(NUMERIC);
DROP FUNCTION IF EXISTS pgtool_test_lock_holder();
DROP SCHEMA IF EXISTS pgtool_test CASCADE;
