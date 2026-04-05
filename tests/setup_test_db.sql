-- tests/setup_test_db.sql
-- 创建测试数据库和用户

-- 创建测试数据库（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'pgtool_test') THEN
        CREATE DATABASE pgtool_test;
    END IF;
END $$;

-- 创建测试schema
CREATE SCHEMA IF NOT EXISTS pgtool_test;

-- 创建测试用的表（用于各种统计测试）
CREATE TABLE IF NOT EXISTS test_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    email VARCHAR(200),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS test_orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES test_users(id),
    amount DECIMAL(10,2),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 创建索引（部分有，部分没有 - 用于 missing-indexes 测试）
CREATE INDEX IF NOT EXISTS idx_test_users_status ON test_users(status);
CREATE INDEX IF NOT EXISTS idx_test_orders_user_id ON test_orders(user_id);

-- 创建一个大表（用于 bloat 测试）
CREATE TABLE IF NOT EXISTS test_large_table (
    id SERIAL PRIMARY KEY,
    data TEXT,
    value NUMERIC,
    created_at TIMESTAMP
);

-- 插入大表数据
INSERT INTO test_large_table (data, value, created_at)
SELECT
    md5(random()::text) as data,
    random() * 1000 as value,
    CURRENT_TIMESTAMP - (random() * INTERVAL '365 days') as created_at
FROM generate_series(1, 10000) s
ON CONFLICT DO NOTHING;

-- 创建函数用于模拟慢查询
CREATE OR REPLACE FUNCTION pgtool_test_slow_query(wait_seconds NUMERIC)
RETURNS VOID AS $$
BEGIN
    PERFORM pg_sleep(wait_seconds);
END;
$$ LANGUAGE plpgsql;

-- 创建函数用于模拟锁等待
CREATE OR REPLACE FUNCTION pgtool_test_lock_holder()
RETURNS VOID AS $$
BEGIN
    -- 长时间持有锁
    PERFORM pg_sleep(30);
END;
$$ LANGUAGE plpgsql;

-- 插入测试数据
INSERT INTO test_users (username, email, status)
SELECT
    'user_' || i,
    'user_' || i || '@example.com',
    CASE WHEN i % 10 = 0 THEN 'inactive' ELSE 'active' END
FROM generate_series(1, 1000) i
ON CONFLICT DO NOTHING;

INSERT INTO test_orders (user_id, amount, status)
SELECT
    (random() * 999 + 1)::int,
    random() * 1000,
    CASE WHEN random() > 0.5 THEN 'completed' ELSE 'pending' END
FROM generate_series(1, 5000)
ON CONFLICT DO NOTHING;

-- 更新统计信息
ANALYZE test_users;
ANALYZE test_orders;
ANALYZE test_large_table;
