# Analyze Index-Usage Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pgtool analyze index-usage` command for detailed index usage analysis including unused indexes and missing indexes.

**Architecture:** Query pg_stat_user_indexes and pg_index for comprehensive index analysis. Show scan counts, index size, and usage patterns.

**Tech Stack:** Bash, PostgreSQL SQL, psql

---

## File Structure

- **Create:** `sql/analyze/index_usage.sql`
- **Create:** `commands/analyze/index_usage.sh`
- **Modify:** `commands/analyze/index.sh`
- **Create:** `tests/test_analyze_index_usage.sh`

---

### Task 1: Create SQL

**Files:**
- Create: `sql/analyze/index_usage.sql`

- [ ] **Step 1: Write SQL**

```sql
-- Comprehensive index usage analysis
-- Parameters: min_scans_threshold (default 0)
-- Output: schema, table, index, index_type, scans, tuples_read, tuples_fetched, index_size, status

WITH index_stats AS (
    SELECT
        schemaname AS schema_name,
        relname AS table_name,
        indexrelname AS index_name,
        idx_scan AS index_scans,
        idx_tup_read AS tuples_read,
        idx_tup_fetch AS tuples_fetched,
        pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
        pg_relation_size(indexrelid) AS size_bytes
    FROM pg_stat_user_indexes
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
),
index_details AS (
    SELECT
        n.nspname AS schema_name,
        t.relname AS table_name,
        i.relname AS index_name,
        CASE
            WHEN ix.indisprimary THEN 'PRIMARY KEY'
            WHEN ix.indisunique THEN 'UNIQUE'
            ELSE 'INDEX'
        END AS index_type,
        ix.indisvalid AS is_valid
    FROM pg_index ix
    JOIN pg_class i ON i.oid = ix.indexrelid
    JOIN pg_class t ON t.oid = ix.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
)
SELECT
    s.schema_name AS schema,
    s.table_name AS table,
    s.index_name AS index,
    d.index_type AS type,
    COALESCE(s.index_scans, 0) AS scans,
    COALESCE(s.tuples_read, 0) AS tuples_read,
    COALESCE(s.tuples_fetched, 0) AS tuples_fetched,
    s.index_size AS size,
    CASE
        WHEN d.is_valid = false THEN 'INVALID'
        WHEN COALESCE(s.index_scans, 0) = 0 THEN 'UNUSED'
        WHEN COALESCE(s.index_scans, 0) < 10 THEN 'RARELY USED'
        ELSE 'ACTIVE'
    END AS status
FROM index_stats s
JOIN index_details d ON s.schema_name = d.schema_name
    AND s.table_name = d.table_name
    AND s.index_name = d.index_name
ORDER BY s.size_bytes DESC
LIMIT 100;
```

- [ ] **Step 2: Commit**

```bash
git add sql/analyze/index_usage.sql
git commit -m "feat(analyze): add SQL for index-usage analysis"
```

---

### Task 2: Create Command

**Files:**
- Create: `commands/analyze/index_usage.sh`

- [ ] **Step 1: Write script**

```bash
#!/bin/bash
# commands/analyze/index_usage.sh

pgtool_analyze_index_usage() {
    local -a opts=()
    local min_scans=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_analyze_index_usage_help
                return 0
                ;;
            --min-scans)
                shift
                min_scans="$1"
                shift
                ;;
            --unused-only)
                min_scans=0
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "索引使用分析"
    echo ""

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "analyze" "index_usage"); then
        pgtool_fatal "SQL文件未找到: analyze/index_usage"
    fi

    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        -v min_scans="$min_scans" \
        --file="$sql_file" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # Warn if there are unused indexes
    if echo "$result" | grep -q "UNUSED"; then
        echo ""
        pgtool_warn "发现未使用的索引，考虑删除以节省空间"
    fi

    return $EXIT_SUCCESS
}

pgtool_analyze_index_usage_help() {
    cat <<EOF
索引使用分析

分析索引的使用情况，识别未使用或很少使用的索引。

用法: pgtool analyze index-usage [选项]

选项:
  -h, --help           显示帮助
      --min-scans NUM  最小扫描次数过滤 (默认: 0)
      --unused-only    仅显示未使用的索引

示例:
  pgtool analyze index-usage
  pgtool analyze index-usage --unused-only
  pgtool analyze index-usage --min-scans=100
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/analyze/index_usage.sh
chmod +x commands/analyze/index_usage.sh
git commit -m "feat(analyze): add index-usage command implementation"
```

---

### Task 3: Register

- [ ] **Step 1: Update index.sh**

Add "index-usage:索引使用分析" to PGTOOL_ANALYZE_COMMANDS.

- [ ] **Step 2: Commit**

```bash
git add commands/analyze/index.sh
git commit -m "feat(analyze): register index-usage command"
```

---

### Task 4: Tests

**Files:**
- Create: `tests/test_analyze_index_usage.sh`

- [ ] **Step 1: Write tests**

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test_runner.sh"

test_files() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/analyze/index_usage.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/analyze/index_usage.sh ]]"
}

test_registered() {
    source "$PGTOOL_ROOT/commands/analyze/index.sh"
    assert_contains "$PGTOOL_ANALYZE_COMMANDS" "index-usage"
}

echo ""
echo "Analyze Index-Usage Tests:"
run_test "test_files" "Files exist"
run_test "test_registered" "Command registered"
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_analyze_index_usage.sh
chmod +x tests/test_analyze_index_usage.sh
git commit -m "test(analyze): add tests for index-usage command"
```
