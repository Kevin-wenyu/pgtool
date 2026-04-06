# Maintenance Command Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `maintenance` command group with vacuum, reindex, and analyze commands for PostgreSQL maintenance tasks.

**Architecture:** Follows pgtool's modular pattern - lib/maintenance.sh for shared functions, commands/maintenance/*.sh for command implementations, sql/maintenance/*.sql for SQL templates.

**Tech Stack:** Bash, PostgreSQL SQL, psql CLI

---

## Files to Create

- `lib/maintenance.sh` - Shared maintenance utility functions
- `commands/maintenance/index.sh` - Command group index and registration
- `commands/maintenance/vacuum.sh` - Vacuum command implementation
- `commands/maintenance/reindex.sh` - Reindex command implementation
- `commands/maintenance/analyze.sh` - Analyze command implementation
- `sql/maintenance/vacuum.sql` - Vacuum SQL template
- `sql/maintenance/reindex.sql` - Reindex SQL template
- `sql/maintenance/analyze.sql` - Analyze SQL template
- `tests/test_maintenance.sh` - Unit tests for maintenance commands

## Files to Modify

- `pgtool.sh` - Add `source "$PGTOOL_SCRIPT_DIR/lib/maintenance.sh"`
- `lib/cli.sh` - Add `maintenance` to the dispatch case statement

---

### Task 1: Create Library File (lib/maintenance.sh)

**Files:**
- Create: `lib/maintenance.sh`

- [ ] **Step 1: Write the library file**

```bash
#!/bin/bash
# lib/maintenance.sh - Maintenance command group utilities

# Check dependencies
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

# Get list of tables needing vacuum
pgtool_maintenance_tables_needing_vacuum() {
    local threshold="${1:-10}"
    psql "${PGTOOL_CONN_OPTS[@]}" -t -c "
        SELECT schemaname || '.' || relname
        FROM pg_stat_user_tables
        WHERE n_dead_tup > $threshold * 1000
        ORDER BY n_dead_tup DESC
    " 2>/dev/null
}

# Get list of bloated indexes
pgtool_maintenance_bloated_indexes() {
    psql "${PGTOOL_CONN_OPTS[@]}" -t -c "
        SELECT schemaname || '.' || indexrelname
        FROM pg_stat_user_indexes i
        JOIN pg_index pi ON i.indexrelname = pi.indexrelname
        WHERE pg_relation_size(indexrelid) > pg_relation_size(relid) * 0.3
        AND pi.indisvalid
    " 2>/dev/null
}

# Check if table exists
pgtool_maintenance_table_exists() {
    local table_name="$1"
    local result
    result=$(psql "${PGTOOL_CONN_OPTS[@]}" -t -c "
        SELECT 1 FROM pg_tables 
        WHERE schemaname || '.' || tablename = '$table_name'
        OR tablename = '$table_name'
        LIMIT 1
    " 2>/dev/null)
    [[ "$result" == " 1" ]]
}
```

- [ ] **Step 2: Make file executable**

Run: `chmod +x lib/maintenance.sh`

- [ ] **Step 3: Commit**

```bash
git add lib/maintenance.sh
git commit -m "feat(maintenance): add maintenance utility library"
```

---

### Task 2: Create Command Group Index (commands/maintenance/index.sh)

**Files:**
- Create: `commands/maintenance/index.sh`

- [ ] **Step 1: Write the index file**

```bash
#!/bin/bash
# commands/maintenance/index.sh - Maintenance command group

PGTOOL_MAINTENANCE_COMMANDS="vacuum:执行VACUUM操作清理表,reindex:重建索引,analyze:更新表统计信息"

pgtool_maintenance_help() {
    cat <<EOF
维护类命令 - PostgreSQL数据库维护操作

可用命令:
  vacuum      执行VACUUM操作清理死亡元组
  reindex     重建索引消除膨胀
  analyze     更新表统计信息

使用 'pgtool maintenance <命令> --help' 查看具体命令帮助

示例:
  pgtool maintenance vacuum --table=users
  pgtool maintenance reindex --index=idx_users_email
  pgtool maintenance analyze --schema=public
EOF
}
```

- [ ] **Step 2: Make file executable**

Run: `chmod +x commands/maintenance/index.sh`

- [ ] **Step 3: Commit**

```bash
git add commands/maintenance/index.sh
git commit -m "feat(maintenance): add command group index"
```

---

### Task 3: Create Vacuum Command

**Files:**
- Create: `commands/maintenance/vacuum.sh`
- Create: `sql/maintenance/vacuum.sql`

- [ ] **Step 1: Write the SQL template**

File: `sql/maintenance/vacuum.sql`
```sql
-- sql/maintenance/vacuum.sql
-- VACUUM 操作 - 清理死亡元组

-- 获取需要vacuum的表
SELECT 
    schemaname || '.' || relname as table_name,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 2) as dead_ratio,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    vacuum_count + autovacuum_count as vacuum_count
FROM pg_stat_user_tables
WHERE n_dead_tup > :threshold * 1000
ORDER BY n_dead_tup DESC;
```

- [ ] **Step 2: Write the command script**

File: `commands/maintenance/vacuum.sh`
```bash
#!/bin/bash
# commands/maintenance/vacuum.sh - VACUUM操作

pgtool_maintenance_vacuum() {
    local table=""
    local dry_run=false
    local full=false
    local analyze=false
    local threshold=10

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_maintenance_vacuum_help
                return 0
                ;;
            --table)
                shift
                table="$1"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --full)
                full=true
                shift
                ;;
            --analyze)
                analyze=true
                shift
                ;;
            --threshold)
                shift
                threshold="$1"
                shift
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            -*)
                pgtool_error "未知选项: $1"
                return $EXIT_INVALID_ARGS
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "检查需要VACUUM的表..."
    echo ""

    # 测试连接
    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    # 查找SQL文件
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "maintenance" "vacuum"); then
        pgtool_fatal "SQL文件未找到: maintenance/vacuum"
    fi

    # 执行SQL查询
    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT:-table}")

    result=$(sed "s/:threshold/${threshold}/g" "$sql_file" | timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # 如果不是dry-run，执行vacuum
    if [[ "$dry_run" == false ]]; then
        echo ""
        if [[ -n "$table" ]]; then
            pgtool_info "执行VACUUM on $table..."
            local vacuum_cmd="VACUUM"
            [[ "$full" == true ]] && vacuum_cmd="VACUUM FULL"
            [[ "$analyze" == true ]] && vacuum_cmd="${vacuum_cmd} ANALYZE"
            
            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "$vacuum_cmd $table" 2>&1; then
                pgtool_info "VACUUM完成: $table"
            else
                pgtool_error "VACUUM失败: $table"
                return $EXIT_SQL_ERROR
            fi
        fi
    fi

    return $EXIT_SUCCESS
}

pgtool_maintenance_vacuum_help() {
    cat << 'EOF'
执行VACUUM操作清理死亡元组

用法: pgtool maintenance vacuum [选项]

选项:
  -h, --help              显示帮助
      --table=<name>      指定表名（默认显示所有需要vacuum的表）
      --dry-run           仅显示需要vacuum的表，不执行操作
      --full              执行VACUUM FULL（需要排他锁）
      --analyze           VACUUM后执行ANALYZE
      --threshold=<n>     死亡元组阈值（千行，默认10）

说明:
  VACUUM回收死亡元组占用的存储空间，防止表膨胀。
  VACUUM FULL完全重写表，需要排他锁，时间更长。

示例:
  # 查看需要vacuum的表
  pgtool maintenance vacuum --dry-run

  # vacuum指定表
  pgtool maintenance vacuum --table=users

  # vacuum并更新统计信息
  pgtool maintenance vacuum --table=users --analyze

  # 使用更低阈值（5千死亡元组）
  pgtool maintenance vacuum --threshold=5
EOF
}
```

- [ ] **Step 3: Make files executable and commit**

```bash
chmod +x commands/maintenance/vacuum.sh
mkdir -p sql/maintenance
git add commands/maintenance/vacuum.sh sql/maintenance/vacuum.sql
git commit -m "feat(maintenance): add vacuum command"
```

---

### Task 4: Create Reindex Command

**Files:**
- Create: `commands/maintenance/reindex.sh`
- Create: `sql/maintenance/reindex.sql`

- [ ] **Step 1: Write the SQL template**

File: `sql/maintenance/reindex.sql`
```sql
-- sql/maintenance/reindex.sql
-- 检查膨胀索引

SELECT 
    schemaname || '.' || indexrelname as index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    pg_size_pretty(pg_relation_size(relid)) as table_size,
    round(pg_relation_size(indexrelid)::numeric / nullif(pg_relation_size(relid), 0), 2) as size_ratio,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid) - pg_relation_size(relid) * 0.3) as estimated_bloat
FROM pg_stat_user_indexes
WHERE pg_relation_size(indexrelid) > pg_relation_size(relid) * :min_ratio
ORDER BY pg_relation_size(indexrelid) DESC;
```

- [ ] **Step 2: Write the command script**

File: `commands/maintenance/reindex.sh`
```bash
#!/bin/bash
# commands/maintenance/reindex.sh - 重建索引

pgtool_maintenance_reindex() {
    local index=""
    local table=""
    local dry_run=false
    local concurrent=true
    local min_ratio=0.3

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_maintenance_reindex_help
                return 0
                ;;
            --index)
                shift
                index="$1"
                shift
                ;;
            --table)
                shift
                table="$1"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --no-concurrent)
                concurrent=false
                shift
                ;;
            --min-ratio)
                shift
                min_ratio="$1"
                shift
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            -*)
                pgtool_error "未知选项: $1"
                return $EXIT_INVALID_ARGS
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "检查膨胀索引..."
    echo ""

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "maintenance" "reindex"); then
        pgtool_fatal "SQL文件未找到: maintenance/reindex"
    fi

    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT:-table}")

    result=$(sed "s/:min_ratio/${min_ratio}/g" "$sql_file" | timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # 执行reindex
    if [[ "$dry_run" == false ]]; then
        echo ""
        local reindex_cmd="REINDEX"
        [[ "$concurrent" == true ]] && reindex_cmd="REINDEX INDEX CONCURRENTLY"
        
        if [[ -n "$index" ]]; then
            pgtool_info "重建索引: $index"
            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "$reindex_cmd $index" 2>&1; then
                pgtool_info "索引重建完成: $index"
            else
                pgtool_error "索引重建失败: $index"
                return $EXIT_SQL_ERROR
            fi
        elif [[ -n "$table" ]]; then
            pgtool_info "重建表的所有索引: $table"
            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "REINDEX TABLE CONCURRENTLY $table" 2>&1; then
                pgtool_info "表索引重建完成: $table"
            else
                pgtool_error "表索引重建失败: $table"
                return $EXIT_SQL_ERROR
            fi
        fi
    fi

    return $EXIT_SUCCESS
}

pgtool_maintenance_reindex_help() {
    cat << 'EOF'
重建索引消除膨胀

用法: pgtool maintenance reindex [选项]

选项:
  -h, --help              显示帮助
      --index=<name>      指定索引名
      --table=<name>      指定表名（重建该表所有索引）
      --dry-run           仅显示膨胀索引，不执行操作
      --no-concurrent     不使用CONCURRENTLY（需要锁）
      --min-ratio=<n>     最小膨胀比例（默认0.3）

说明:
  REINDEX重建索引，消除因更新删除导致的索引膨胀。
  默认使用CONCURRENTLY选项，不阻塞读写。

示例:
  # 查看膨胀索引
  pgtool maintenance reindex --dry-run

  # 重建指定索引
  pgtool maintenance reindex --index=idx_users_email

  # 重建表的所有索引
  pgtool maintenance reindex --table=users
EOF
}
```

- [ ] **Step 3: Make files executable and commit**

```bash
chmod +x commands/maintenance/reindex.sh
git add commands/maintenance/reindex.sh sql/maintenance/reindex.sql
git commit -m "feat(maintenance): add reindex command"
```

---

### Task 5: Create Analyze Command

**Files:**
- Create: `commands/maintenance/analyze.sh`
- Create: `sql/maintenance/analyze.sql`

- [ ] **Step 1: Write the SQL template**

File: `sql/maintenance/analyze.sql`
```sql
-- sql/maintenance/analyze.sql
-- 检查需要ANALYZE的表

SELECT 
    schemaname || '.' || relname as table_name,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    last_analyze,
    last_autoanalyze,
    round(EXTRACT(EPOCH FROM (now() - GREATEST(last_analyze, last_autoanalyze))) / 3600, 1) as hours_since_analyze,
    analyze_count + autoanalyze_count as analyze_count,
    CASE 
        WHEN n_live_tup > 10000 AND last_analyze IS NULL THEN 'NEEDED'
        WHEN EXTRACT(EPOCH FROM (now() - GREATEST(last_analyze, last_autoanalyze))) > :hours * 3600 THEN 'STALE'
        ELSE 'OK'
    END as status
FROM pg_stat_user_tables
WHERE n_live_tup > 0
ORDER BY EXTRACT(EPOCH FROM (now() - GREATEST(last_analyze, last_autoanalyze))) DESC NULLS FIRST;
```

- [ ] **Step 2: Write the command script**

File: `commands/maintenance/analyze.sh`
```bash
#!/bin/bash
# commands/maintenance/analyze.sh - ANALYZE操作

pgtool_maintenance_analyze() {
    local table=""
    local schema=""
    local dry_run=false
    local hours=24

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_maintenance_analyze_help
                return 0
                ;;
            --table)
                shift
                table="$1"
                shift
                ;;
            --schema)
                shift
                schema="$1"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --hours)
                shift
                hours="$1"
                shift
                ;;
            --format|--timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            -*)
                pgtool_error "未知选项: $1"
                return $EXIT_INVALID_ARGS
                ;;
            *)
                shift
                ;;
        esac
    done

    pgtool_info "检查统计信息状态..."
    echo ""

    if ! pgtool_pg_test_connection >/dev/null 2>&1; then
        return $EXIT_CONNECTION_ERROR
    fi

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "maintenance" "analyze"); then
        pgtool_fatal "SQL文件未找到: maintenance/analyze"
    fi

    local result
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT:-table}")

    result=$(sed "s/:hours/${hours}/g" "$sql_file" | timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --pset=pager=off \
        $format_args \
        2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL执行超时"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    echo "$result"

    # 执行analyze
    if [[ "$dry_run" == false ]]; then
        echo ""
        if [[ -n "$table" ]]; then
            pgtool_info "执行ANALYZE: $table"
            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "ANALYZE $table" 2>&1; then
                pgtool_info "ANALYZE完成: $table"
            else
                pgtool_error "ANALYZE失败: $table"
                return $EXIT_SQL_ERROR
            fi
        elif [[ -n "$schema" ]]; then
            pgtool_info "执行ANALYZE: schema $schema"
            if timeout "$PGTOOL_TIMEOUT" psql "${PGTOOL_CONN_OPTS[@]}" -c "ANALYZE $schema" 2>&1; then
                pgtool_info "Schema ANALYZE完成: $schema"
            else
                pgtool_error "Schema ANALYZE失败: $schema"
                return $EXIT_SQL_ERROR
            fi
        fi
    fi

    return $EXIT_SUCCESS
}

pgtool_maintenance_analyze_help() {
    cat << 'EOF'
更新表统计信息

用法: pgtool maintenance analyze [选项]

选项:
  -h, --help              显示帮助
      --table=<name>      指定表名
      --schema=<name>     指定模式名
      --dry-run           仅显示统计信息状态，不执行操作
      --hours=<n>         统计信息过期小时数（默认24）

说明:
  ANALYZE更新表的统计信息，帮助优化器生成更好的执行计划。
  建议在大量数据加载或批量更新后执行。

示例:
  # 查看统计信息状态
  pgtool maintenance analyze --dry-run

  # analyze指定表
  pgtool maintenance analyze --table=users

  # analyze整个schema
  pgtool maintenance analyze --schema=public

  # 查看超过48小时未analyze的表
  pgtool maintenance analyze --hours=48 --dry-run
EOF
}
```

- [ ] **Step 3: Make files executable and commit**

```bash
chmod +x commands/maintenance/analyze.sh
git add commands/maintenance/analyze.sh sql/maintenance/analyze.sql
git commit -m "feat(maintenance): add analyze command"
```

---

### Task 6: Register in Main Script

**Files:**
- Modify: `pgtool.sh` (add source line)
- Modify: `lib/cli.sh` (add maintenance to dispatch)

- [ ] **Step 1: Add source line in pgtool.sh**

Add after line 25 (after lib/config.sh):
```bash
source "$PGTOOL_SCRIPT_DIR/lib/maintenance.sh"
```

- [ ] **Step 2: Add to cli.sh dispatch**

Find the case statement in pgtool_dispatch() and add `maintenance`:
```bash
check|stat|admin|analyze|monitor|plugin|maintenance)
```

- [ ] **Step 3: Commit**

```bash
git add pgtool.sh lib/cli.sh
git commit -m "feat(maintenance): register maintenance command group"
```

---

### Task 7: Create Tests

**Files:**
- Create: `tests/test_maintenance.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/bin/bash
# tests/test_maintenance.sh - Maintenance command group tests

set -e

PGTOOL_ROOT="${PGTOOL_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}"
source "$PGTOOL_ROOT/tests/test_runner.sh"
source "$PGTOOL_ROOT/lib/maintenance.sh"

test_maintenance_lib_loaded() {
    assert_true "$(type pgtool_maintenance_tables_needing_vacuum &>/dev/null && echo 0 || echo 1)" "maintenance库应该加载"
}

test_maintenance_commands_exist() {
    local cmds=("vacuum" "reindex" "analyze")
    for cmd in "${cmds[@]}"; do
        assert_true "$(test -f "$PGTOOL_ROOT/commands/maintenance/${cmd}.sh" && echo 0 || echo 1)" "命令 ${cmd}.sh 应该存在"
    done
}

test_maintenance_index_exists() {
    assert_true "$(test -f "$PGTOOL_ROOT/commands/maintenance/index.sh" && echo 0 || echo 1)" "maintenance/index.sh 应该存在"
}

test_maintenance_sql_files_exist() {
    local sqls=("vacuum" "reindex" "analyze")
    for sql in "${sqls[@]}"; do
        assert_true "$(test -f "$PGTOOL_ROOT/sql/maintenance/${sql}.sql" && echo 0 || echo 1)" "SQL ${sql}.sql 应该存在"
    done
}

# Run tests
run_test "test_maintenance_lib_loaded"
run_test "test_maintenance_commands_exist"
run_test "test_maintenance_index_exists"
run_test "test_maintenance_sql_files_exist"
```

- [ ] **Step 2: Make file executable and commit**

```bash
chmod +x tests/test_maintenance.sh
git add tests/test_maintenance.sh
git commit -m "test(maintenance): add unit tests for maintenance command group"
```

---

## Verification Checklist

After all tasks complete, verify:

- [ ] `./pgtool.sh maintenance --help` shows help
- [ ] `./pgtool.sh maintenance vacuum --help` works
- [ ] `./pgtool.sh maintenance reindex --help` works
- [ ] `./pgtool.sh maintenance analyze --help` works
- [ ] `cd tests && ./run.sh test_maintenance` passes all tests
