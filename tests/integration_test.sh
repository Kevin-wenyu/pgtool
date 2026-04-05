#!/bin/bash
# tests/integration_test.sh - pgtool 集成测试
# 在真实 PostgreSQL 数据库中测试所有命令

set -euo pipefail

# 脚本路径
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PGTOOL_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 测试统计
PASSED=0
FAILED=0
SKIPPED=0

# 测试数据库
TEST_DB="${PGTOOL_TEST_DB:-pgtool_test}"

# 检查测试数据库
if ! psql -d "$TEST_DB" -c "SELECT 1" >/dev/null 2>&1; then
    echo -e "${RED}错误: 无法连接到测试数据库 '$TEST_DB'${NC}"
    echo "请确保测试数据库已创建: createdb $TEST_DB"
    exit 1
fi

echo "pgtool 集成测试"
echo "==============="
echo ""
echo "测试数据库: $TEST_DB"
echo ""

# 运行测试的辅助函数
run_test() {
    local name="$1"
    local command="$2"
    local expected="${3:-}"

    echo -n "测试: $name ... "

    local output
    local exit_code

    if output=$(eval "$command" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    # 过滤 DEBUG 信息
    output=$(echo "$output" | grep -v '\[DEBUG\]' || true)

    if [[ -n "$expected" ]]; then
        if echo "$output" | grep -q "$expected"; then
            echo -e "${GREEN}PASS${NC}"
            ((PASSED++)) || true
        else
            echo -e "${RED}FAIL${NC}"
            echo "  期望包含: $expected"
            echo "  实际输出: $(echo "$output" | head -3)"
            ((FAILED++)) || true
        fi
    elif [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((PASSED++)) || true
    else
        echo -e "${RED}FAIL${NC} (exit code: $exit_code)"
        echo "  输出: $(echo "$output" | head -3)"
        ((FAILED++)) || true
    fi
}

skip_test() {
    local name="$1"
    local reason="${2:-}"
    echo -e "测试: $name ... ${YELLOW}SKIP${NC}${reason:+ ($reason)}"
    ((SKIPPED++)) || true
}

echo "========================================"
echo "Check 命令组测试"
echo "========================================"

run_test "check xid" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh check xid" \
    "XID Age"

run_test "check connection" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh check connection" \
    "Max Connections"

run_test "check autovacuum" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh check autovacuum" \
    "Running Autovacuum"

# 复制测试（仅在主库且有复制时有效）
if psql -d "$TEST_DB" -t -c "SELECT pg_is_in_recovery()" 2>/dev/null | grep -q "f"; then
    if psql -d "$TEST_DB" -t -c "SELECT count(*) FROM pg_stat_replication" 2>/dev/null | tr -d ' ' | grep -q "^[1-9]"; then
        run_test "check replication (with replicas)" \
            "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh check replication" \
            "replication"
    else
        run_test "check replication (no replicas)" \
            "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh check replication" \
            "主库"
    fi
else
    skip_test "check replication (standby)" "当前是备库"
fi

echo ""
echo "========================================"
echo "Stat 命令组测试"
echo "========================================"

run_test "stat activity" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh stat activity" \
    "PID"

run_test "stat locks" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh stat locks" \
    "当前没有锁等待"

run_test "stat database" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh stat database" \
    "$TEST_DB"

run_test "stat table" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh stat table" \
    "Table"

run_test "stat indexes" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh stat indexes" \
    "Index"

echo ""
echo "========================================"
echo "Analyze 命令组测试"
echo "========================================"

run_test "analyze bloat" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh analyze bloat" \
    ""

run_test "analyze missing-indexes" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh analyze missing-indexes" \
    ""

run_test "analyze slow-queries" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh analyze slow-queries" \
    ""

run_test "analyze vacuum-stats" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh analyze vacuum-stats" \
    "Vacuum"

echo ""
echo "========================================"
echo "Admin 命令组测试"
echo "========================================"

run_test "admin checkpoint" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh admin checkpoint --force" \
    "检查点"

# reload 测试需要超级用户权限
if psql -d "$TEST_DB" -c "SELECT pg_reload_conf()" >/dev/null 2>&1; then
    run_test "admin reload" \
        "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh admin reload --force" \
        "配置"
else
    skip_test "admin reload" "需要超级用户权限"
fi

# kill-blocking 和 cancel-query 需要特殊场景
skip_test "admin kill-blocking" "需要阻塞场景"
skip_test "admin cancel-query" "需要长时间运行查询"

echo ""
echo "========================================"
echo "Plugin 命令组测试"
echo "========================================"

run_test "plugin list" \
    "$PGTOOL_ROOT/pgtool.sh plugin list" \
    "example"

run_test "plugin example hello" \
    "$PGTOOL_ROOT/pgtool.sh plugin example hello" \
    "Hello"

echo ""
echo "========================================"
echo "格式选项测试"
echo "========================================"

run_test "format=csv" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh --format=csv check connection" \
    ","

run_test "format=unaligned" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh --format=unaligned check connection" \
    ""

echo ""
echo "========================================"
echo "错误处理测试"
echo "========================================"

run_test "invalid database" \
    "PGDATABASE=nonexistent_db12345 $PGTOOL_ROOT/pgtool.sh check xid 2>&1 || true" \
    "无法连接"

run_test "invalid command" \
    "PGDATABASE=$TEST_DB $PGTOOL_ROOT/pgtool.sh invalid_cmd 2>&1; true" \
    "未知"

echo ""
echo "========================================"
echo "测试汇总"
echo "========================================"
echo -e "通过: ${GREEN}$PASSED${NC}"
[[ $FAILED -gt 0 ]] && echo -e "失败: ${RED}$FAILED${NC}" || echo "失败: $FAILED"
[[ $SKIPPED -gt 0 ]] && echo -e "跳过: ${YELLOW}$SKIPPED${NC}" || echo "跳过: $SKIPPED"
echo "总计: $((PASSED + FAILED + SKIPPED))"
echo "========================================"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}所有测试通过!${NC}"
    exit 0
else
    echo -e "${RED}有测试失败${NC}"
    exit 1
fi
