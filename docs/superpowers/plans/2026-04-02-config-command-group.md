# Config Command Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `config` command group for PostgreSQL configuration analysis, optimization recommendations, and management.

**Architecture:** Query pg_settings, apply best-practice rules based on PG version and system resources, generate ALTER SYSTEM commands with --dry-run support.

**Tech Stack:** Bash, psql, system resource detection (/proc/meminfo, sysctl)

---

## File Structure

| File | Type | Purpose |
|------|------|---------|
| `commands/config/index.sh` | Create | Command group index |
| `commands/config/analyze.sh` | Create | Config analysis with recommendations |
| `commands/config/diff.sh` | Create | Compare configs between instances |
| `commands/config/get.sh` | Create | Get specific parameter value |
| `commands/config/set.sh` | Create | Generate ALTER SYSTEM commands |
| `commands/config/reset.sh` | Create | Show reset commands |
| `commands/config/export.sh` | Create | Export configuration |
| `lib/config.sh` | Create | Config utility functions |
| `lib/config_rules.sh` | Create | Best practice rules |
| `sql/config/analyze.sql` | Create | Full config query |
| `sql/config/get.sql` | Create | Single parameter query |
| `lib/cli.sh` | Modify | Add "config" to PGTOOL_GROUPS |
| `tests/test_config.sh` | Create | Unit tests |

---

## Task 1: Create Config Rules Library (lib/config_rules.sh)

**Files:**
- Create: `lib/config_rules.sh`

- [ ] **Step 1: Write config rules**

```bash
#!/bin/bash
# lib/config_rules.sh - PostgreSQL configuration best practice rules

#==============================================================================
# Rule Format: name|category|check_type|threshold|recommendation|severity
#==============================================================================

# Memory configuration rules
pgtool_config_rules_memory() {
    cat <<'RULES'
shared_buffers|memory|percent_of_ram|25|Set to 25% of RAM (max 8GB on Linux)|warning
effective_cache_size|memory|percent_of_ram|50|Set to 50% of RAM|warning
work_mem|memory|formula|total_ram/max_connections/4|Based on workload, watch for temp file creation|info
maintenance_work_mem|memory|min|1048576|Set at least 1GB for maintenance operations|warning
huge_pages|memory|value|try|Use huge pages for large shared_buffers|info
RULES
}

# Connection rules
pgtool_config_rules_connections() {
    cat <<'RULES'
max_connections|connections|max|500|Consider using connection pooler if > 500|warning
listen_addresses|connections|value|localhost|Restrict listen_addresses in production|warning
ssl|connections|value|on|Enable SSL in production|critical
ssl_min_protocol_version|connections|value|TLSv1.2|Use TLS 1.2 or higher|warning
RULES
}

# WAL rules
pgtool_config_rules_wal() {
    cat <<'RULES'
wal_level|wal|value|replica|Set wal_level to replica or higher|critical
wal_buffers|wal|auto|-1|Keep at -1 (auto-tuned)|info
min_wal_size|wal|min|1048576|Set at least 1GB|warning
max_wal_size|wal|min|4194304|Set at least 4GB|warning
max_wal_senders|wal|min|2|Set at least 2 for replication|warning
wal_keep_size|wal|min|1024|Keep at least 1GB of WAL|warning
archive_mode|wal|value|on|Enable WAL archiving for backups|warning
archive_timeout|wal|max|300|Archive at least every 5 minutes|info
RULES
}

# Vacuum rules
pgtool_config_rules_vacuum() {
    cat <<'RULES'
autovacuum|vacuum|value|on|Keep autovacuum enabled|critical
autovacuum_max_workers|vacuum|min|3|Set at least 3 workers|warning
autovacuum_naptime|vacuum|max|60|Set to 60s or less|warning
autovacuum_vacuum_scale_factor|vacuum|max|0.1|Consider lowering for large tables|info
RULES
}

# Replication rules
pgtool_config_rules_replication() {
    cat <<'RULES'
wal_level|replication|value|replica|Set wal_level to replica or higher|critical
max_wal_senders|replication|min|2|Set at least 2 for replication|warning
hot_standby|replication|value|on|Enable hot_standby for replicas|warning
hot_standby_feedback|replication|value|on|Enable to reduce replication conflicts|info
max_replication_slots|replication|min|2|Set at least 2 for logical replication|warning
RULES
}

# Logging rules
pgtool_config_rules_logging() {
    cat <<'RULES'
logging_collector|logging|value|on|Enable logging collector|warning
log_line_prefix|logging|value|%m [%p] %q%u@%d |Use timestamp, pid, user, database|info
log_checkpoints|logging|value|on|Log checkpoints|warning
log_connections|logging|value|on|Log connections|info
log_disconnections|logging|value|on|Log disconnections|info
log_lock_waits|logging|value|on|Log lock waits > deadlock_timeout|info
log_min_duration_statement|logging|max|1000|Log slow queries (>1s) for analysis|info
log_autovacuum_min_duration|logging|max|0|Log all autovacuum operations|info
RULES
}

# Query planner rules
pgtool_config_rules_planner() {
    cat <<'RULES'
random_page_cost|planner|value|1.1|Set to 1.1 for SSD storage|warning
effective_io_concurrency|planner|value|200|Set high for SSD/NVMe|warning
max_parallel_workers_per_gather|planner|min|2|Enable parallel queries|info
max_parallel_workers|planner|min|4|Set based on CPU cores|info
max_parallel_maintenance_workers|planner|min|2|Enable parallel index/VACUUM|info
RULES
}

# Security rules
pgtool_config_rules_security() {
    cat <<'RULES'
password_encryption|security|value|scram-sha-256|Use SCRAM-SHA-256|warning
shared_preload_libraries|security|contains|passwordcheck|Consider passwordcheck module|info
log_replication_commands|security|value|on|Log replication commands|info
RULES
}

# Get all rules
pgtool_config_rules_all() {
    pgtool_config_rules_memory
    pgtool_config_rules_connections
    pgtool_config_rules_wal
    pgtool_config_rules_vacuum
    pgtool_config_rules_replication
    pgtool_config_rules_logging
    pgtool_config_rules_planner
    pgtool_config_rules_security
}

# Get rules by category
pgtool_config_rules_by_category() {
    local category="$1"
    pgtool_config_rules_all | grep "|$category|"
}

#==============================================================================
# Rule Checking Functions
#==============================================================================

# Check if value meets rule
pgtool_config_check_rule() {
    local name="$1"
    local current="$2"
    local rule_type="$3"
    local threshold="$4"
    local total_ram="${5:-0}"
    local max_conn="${6:-100}"

    case "$rule_type" in
        value)
            [[ "$current" == "$threshold" ]]
            ;;
        min)
            local current_val
            current_val=$(pgtool_config_parse_value "$current")
            [[ "$current_val" -ge "$threshold" ]]
            ;;
        max)
            local current_val
            current_val=$(pgtool_config_parse_value "$current")
            [[ "$current_val" -le "$threshold" ]]
            ;;
        percent_of_ram)
            local expected=$((total_ram * threshold / 100))
            local current_val
            current_val=$(pgtool_config_parse_value "$current")
            [[ "$current_val" -ge "$expected" ]]
            ;;
        formula)
            # For formula rules, just return true (recommendation only)
            return 0
            ;;
        contains)
            [[ "$current" == *"$threshold"* ]]
            ;;
        auto)
            [[ "$current" == "$threshold" ]] || [[ "$current" == "auto" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Parse configuration value to bytes
pgtool_config_parse_value() {
    local value="$1"

    # Remove units and convert to bytes
    if [[ "$value" =~ ^([0-9]+)([kmgtpe]?b?)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"

        case "${unit,,}" in
            k|kb) echo $((num * 1024)) ;;
            m|mb) echo $((num * 1024 * 1024)) ;;
            g|gb) echo $((num * 1024 * 1024 * 1024)) ;;
            t|tb) echo $((num * 1024 * 1024 * 1024 * 1024)) ;;
            *) echo "$num" ;;
        esac
    else
        echo "$value"
    fi
}

# Format bytes to human readable
pgtool_config_format_bytes() {
    local bytes="$1"

    if [[ "$bytes" -ge 1099511627776 ]]; then
        echo "${TB}TB"
    elif [[ "$bytes" -ge 1073741824 ]]; then
        echo "$((bytes / 1024 / 1024 / 1024))GB"
    elif [[ "$bytes" -ge 1048576 ]]; then
        echo "$((bytes / 1024 / 1024))MB"
    elif [[ "$bytes" -ge 1024 ]]; then
        echo "$((bytes / 1024))kB"
    else
        echo "${bytes}"
    fi
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/config_rules.sh
git commit -m "feat(config): add configuration best practice rules library"
```

---

## Task 2: Create Config Utilities Library (lib/config.sh)

**Files:**
- Create: `lib/config.sh`

- [ ] **Step 1: Write config utilities**

```bash
#!/bin/bash
# lib/config.sh - Configuration utility functions

#==============================================================================
# System Resource Detection
#==============================================================================

# Detect system memory in kB
pgtool_config_detect_memory() {
    local mem_kb=0

    # Linux
    if [[ -f /proc/meminfo ]]; then
        mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    # macOS/BSD
    elif command -v sysctl &>/dev/null; then
        local mem_bytes
        mem_bytes=$(sysctl -n hw.memsize 2>/dev/null)
        if [[ -n "$mem_bytes" ]]; then
            mem_kb=$((mem_bytes / 1024))
        fi
    fi

    # Fallback: use PostgreSQL's view
    if [[ "$mem_kb" -eq 0 ]]; then
        mem_kb=$(pgtool_pg_query_one "SELECT pg_total_memory() / 1024" 2>/dev/null || echo 0)
    fi

    echo "${mem_kb:-0}"
}

# Detect CPU count
pgtool_config_detect_cpus() {
    local cpus=0

    # Linux
    if [[ -f /proc/cpuinfo ]]; then
        cpus=$(grep -c ^processor /proc/cpuinfo)
    # macOS/BSD
    elif command -v sysctl &>/dev/null; then
        cpus=$(sysctl -n hw.ncpu 2>/dev/null)
    fi

    echo "${cpus:-1}"
}

# Detect disk type (SSD/HDD)
pgtool_config_detect_disk_type() {
    # Simple heuristic based on /sys
    if [[ -d /sys/block ]]; then
        local rotational
        rotational=$(cat /sys/block/sda/queue/rotational 2>/dev/null || echo 1)
        if [[ "$rotational" == "0" ]]; then
            echo "SSD"
        else
            echo "HDD"
        fi
    else
        echo "UNKNOWN"
    fi
}

#==============================================================================
# Configuration Retrieval
#==============================================================================

# Get all configuration parameters
pgtool_config_get_all() {
    pgtool_pg_exec "SELECT name, setting, unit, boot_val, source, context, vartype, short_desc FROM pg_settings ORDER BY category, name" \
        --pset=format=unaligned \
        --pset=fieldsep='|' \
        2>/dev/null
}

# Get specific parameter
pgtool_config_get_param() {
    local name="$1"
    pgtool_pg_exec "SELECT name, setting, unit, boot_val, source, context, vartype, short_desc FROM pg_settings WHERE name = '$name'" \
        --pset=format=unaligned \
        --pset=fieldsep='|' \
        2>/dev/null
}

# Get changed parameters only
pgtool_config_get_changed() {
    pgtool_pg_exec "SELECT name, setting, unit, boot_val, source FROM pg_settings WHERE source != 'default' ORDER BY name" \
        --pset=format=unaligned \
        --pset=fieldsep='|' \
        2>/dev/null
}

# Get parameters by category
pgtool_config_get_by_category() {
    local category="$1"
    pgtool_pg_exec "SELECT name, setting, unit, short_desc FROM pg_settings WHERE category ILIKE '%$category%' ORDER BY name" \
        --pset=format=unaligned \
        --pset=fieldsep='|' \
        2>/dev/null
}

# Get PostgreSQL version
pgtool_config_pg_version() {
    pgtool_pg_query_one "SELECT current_setting('server_version_num')" 2>/dev/null
}

# Get max connections
pgtool_config_get_max_connections() {
    pgtool_pg_query_one "SELECT current_setting('max_connections')" 2>/dev/null
}

#==============================================================================
# Recommendation Calculations
#==============================================================================

# Calculate recommended shared_buffers
pgtool_config_calc_shared_buffers() {
    local total_ram_kb="$1"
    local max_shared=$((8 * 1024 * 1024))  # 8GB max in kB

    local recommended=$((total_ram_kb / 4))  # 25%

    if [[ "$recommended" -gt "$max_shared" ]]; then
        recommended=$max_shared
    fi

    echo "$recommended"
}

# Calculate recommended effective_cache_size
pgtool_config_calc_effective_cache_size() {
    local total_ram_kb="$1"
    echo $((total_ram_kb / 2))  # 50%
}

# Calculate recommended work_mem
pgtool_config_calc_work_mem() {
    local total_ram_kb="$1"
    local max_conn="${2:-100}"

    # work_mem = total_ram / max_conn / 4 (for 25% memory usage)
    local work_mem=$((total_ram_kb / max_conn / 4))

    # Cap at reasonable values
    local min_work_mem=4096      # 4MB
    local max_work_mem=262144    # 256MB

    if [[ "$work_mem" -lt "$min_work_mem" ]]; then
        work_mem=$min_work_mem
    elif [[ "$work_mem" -gt "$max_work_mem" ]]; then
        work_mem=$max_work_mem
    fi

    echo "$work_mem"
}

# Calculate recommended maintenance_work_mem
pgtool_config_calc_maintenance_work_mem() {
    local total_ram_kb="$1"

    # 1GB or 10% of RAM, whichever is smaller
    local one_gb=$((1024 * 1024))
    local ten_percent=$((total_ram_kb / 10))

    if [[ "$ten_percent" -gt "$one_gb" ]]; then
        echo "$one_gb"
    else
        echo "$ten_percent"
    fi
}

#==============================================================================
# Analysis Functions
#==============================================================================

# Analyze a single parameter against rules
pgtool_config_analyze_param() {
    local name="$1"
    local current="$2"
    local total_ram="${3:-0}"
    local max_conn="${4:-100}"

    local issues=()

    # Find matching rules
    local rule
    while IFS='|' read -r rule_name category check_type threshold recommendation severity; do
        if [[ "$rule_name" == "$name" ]]; then
            if ! pgtool_config_check_rule "$name" "$current" "$check_type" "$threshold" "$total_ram" "$max_conn"; then
                local recommended="$threshold"

                # Calculate actual recommendation for formula rules
                if [[ "$check_type" == "formula" ]]; then
                    case "$name" in
                        work_mem)
                            recommended=$(pgtool_config_calc_work_mem "$total_ram" "$max_conn")
                            recommended=$(pgtool_config_format_bytes "$((recommended * 1024))")
                            ;;
                        shared_buffers)
                            recommended=$(pgtool_config_calc_shared_buffers "$total_ram")
                            recommended=$(pgtool_config_format_bytes "$((recommended * 1024))")
                            ;;
                        effective_cache_size)
                            recommended=$(pgtool_config_calc_effective_cache_size "$total_ram")
                            recommended=$(pgtool_config_format_bytes "$((recommended * 1024))")
                            ;;
                        maintenance_work_mem)
                            recommended=$(pgtool_config_calc_maintenance_work_mem "$total_ram")
                            recommended=$(pgtool_config_format_bytes "$((recommended * 1024))")
                            ;;
                    esac
                fi

                issues+=("$severity|$name|$current|$recommended|$recommendation")
            fi
        fi
    done <<< "$(pgtool_config_rules_all)"

    printf '%s\n' "${issues[@]}"
}

#==============================================================================
# Export Functions
#==============================================================================

# Export to postgresql.conf format
pgtool_config_export_conf() {
    local category_filter="${1:-}"

    local sql
    sql="SELECT name || ' = ' || setting FROM pg_settings WHERE source != 'default'"

    if [[ -n "$category_filter" ]]; then
        sql="$sql AND category ILIKE '%$category_filter%'"
    fi

    sql="$sql ORDER BY name"

    echo "# PostgreSQL configuration export"
    echo "# Generated: $(date)"
    echo "# Database: $PGTOOL_DATABASE"
    echo

    pgtool_pg_exec "$sql" --tuples-only --quiet 2>/dev/null
}

# Export to ALTER SYSTEM format
pgtool_config_export_alter_system() {
    local category_filter="${1:-}"

    local sql
    sql="SELECT 'ALTER SYSTEM SET ' || name || ' = ''' || setting || ''';' FROM pg_settings WHERE source != 'default'"

    if [[ -n "$category_filter" ]]; then
        sql="$sql AND category ILIKE '%$category_filter%'"
    fi

    sql="$sql ORDER BY name"

    echo "-- PostgreSQL ALTER SYSTEM export"
    echo "-- Generated: $(date)"
    echo "-- Database: $PGTOOL_DATABASE"
    echo "-- Run: SELECT pg_reload_conf(); -- after applying"
    echo

    pgtool_pg_exec "$sql" --tuples-only --quiet 2>/dev/null
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/config.sh
git commit -m "feat(config): add configuration utility library"
```

---

## Task 3: Create SQL Templates

**Files:**
- Create: `sql/config/analyze.sql`
- Create: `sql/config/get.sql`

- [ ] **Step 1: Write analyze.sql**

```sql
-- sql/config/analyze.sql
-- Full configuration query for analysis
-- Parameters: :category (optional filter)

SELECT
    name AS "Parameter",
    setting AS "Value",
    COALESCE(unit, '') AS "Unit",
    context AS "Context",
    vartype AS "Type",
    source AS "Source",
    boot_val AS "Default",
    category AS "Category",
    short_desc AS "Description"
FROM pg_settings
WHERE (:category = '' OR category ILIKE '%' || :category || '%')
  AND category != 'Custom Variable Classes'
ORDER BY category, name;
```

- [ ] **Step 2: Write get.sql**

```sql
-- sql/config/get.sql
-- Single parameter query
-- Parameters: :name

SELECT
    name AS "Parameter",
    setting AS "Value",
    COALESCE(unit, '') AS "Unit",
    context AS "Context",
    vartype AS "Type",
    boot_val AS "Default",
    source AS "Source",
    category AS "Category",
    short_desc AS "Description",
    extra_desc AS "Extra"
FROM pg_settings
WHERE name = :name;
```

- [ ] **Step 3: Commit**

```bash
git add sql/config/
git commit -m "feat(config): add SQL templates for configuration queries"
```

---

## Task 4: Create Command Group Index

**Files:**
- Create: `commands/config/index.sh`

- [ ] **Step 1: Write index.sh**

```bash
#!/bin/bash
# commands/config/index.sh - config command group index

# Command list: "command:description"
PGTOOL_CONFIG_COMMANDS="analyze:分析配置并提供建议,diff:比较配置差异,get:获取参数值,set:生成设置命令,reset:显示重置命令,export:导出配置"

# Display help
pgtool_config_help() {
    cat <<EOF
配置类命令 - 配置分析与管理

可用命令:
  analyze    分析配置并提供优化建议
  diff       比较两个实例的配置差异
  get        获取特定参数值
  set        生成 ALTER SYSTEM 设置命令
  reset      显示参数重置命令
  export     导出配置到文件

选项:
  -h, --help              显示帮助
      --category CAT      按类别过滤 (memory|replication|logging|wal|vacuum)
      --changed-only      仅显示已更改的参数
      --recommend         显示优化建议

说明:
  analyze 命令基于系统资源和PostgreSQL最佳实践提供配置建议。
  set/export 命令生成 SQL 命令，需要超级用户权限执行。

使用 'pgtool config <命令> --help' 查看具体命令帮助

示例:
  pgtool config analyze
  pgtool config analyze --category=memory --recommend
  pgtool config get shared_buffers
  pgtool config set --param=work_mem --value=256MB
  pgtool config export --changed-only
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/config/index.sh
git commit -m "feat(config): add config command group index"
```

---

## Task 5: Implement Config Analyze Command

**Files:**
- Create: `commands/config/analyze.sh`

- [ ] **Step 1: Write analyze.sh**

```bash
#!/bin/bash
# commands/config/analyze.sh - Config analyze command

#==============================================================================
# Main function
#==============================================================================

pgtool_config_analyze() {
    local -a opts=()
    local -a args=()
    local category=""
    local changed_only=false
    local recommend=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_analyze_help
                return 0
                ;;
            --category)
                shift
                category="$1"
                shift
                ;;
            --changed-only)
                changed_only=true
                shift
                ;;
            --recommend)
                recommend=true
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "分析PostgreSQL配置..."
    echo

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Detect system resources
    local total_ram max_conn pg_version
    total_ram=$(pgtool_config_detect_memory)
    max_conn=$(pgtool_config_get_max_connections)
    pg_version=$(pgtool_config_pg_version)

    echo "系统信息:"
    echo "  内存: $((total_ram / 1024 / 1024))GB"
    echo "  CPU: $(pgtool_config_detect_cpus)"
    echo "  磁盘: $(pgtool_config_detect_disk_type)"
    echo

    echo "数据库信息:"
    echo "  版本: $pg_version"
    echo "  最大连接数: $max_conn"
    echo

    # If --recommend, run rule checks
    if [[ "$recommend" == true ]]; then
        pgtool_config_analyze_recommendations "$total_ram" "$max_conn"
    fi

    # Show configuration
    if [[ "$changed_only" == true ]]; then
        pgtool_config_analyze_changed
    else
        pgtool_config_analyze_all "$category"
    fi
}

# Analyze and show recommendations
pgtool_config_analyze_recommendations() {
    local total_ram="$1"
    local max_conn="$2"

    echo "配置建议:"
    echo "========="
    echo

    local critical_count=0
    local warning_count=0
    local info_count=0

    # Check each rule
    local rule_line
    while IFS='|' read -r name category check_type threshold recommendation severity; do
        # Get current value
        local current
        current=$(pgtool_pg_query_one "SELECT setting FROM pg_settings WHERE name = '$name'" 2>/dev/null)

        if [[ -z "$current" ]]; then
            continue
        fi

        # Check rule
        if ! pgtool_config_check_rule "$name" "$current" "$check_type" "$threshold" "$total_ram" "$max_conn" 2>/dev/null; then
            case "$severity" in
                critical)
                    echo -e "  [CRITICAL] $name"
                    ((critical_count++))
                    ;;
                warning)
                    echo -e "  [WARNING]  $name"
                    ((warning_count++))
                    ;;
                *)
                    echo -e "  [INFO]     $name"
                    ((info_count++))
                    ;;
            esac
            echo "    当前值: $current"

            # Show recommended value
            local recommended="$threshold"
            case "$name" in
                work_mem)
                    recommended=$(pgtool_config_calc_work_mem "$total_ram" "$max_conn")
                    recommended="${recommended}kB"
                    ;;
                shared_buffers)
                    recommended=$(pgtool_config_calc_shared_buffers "$total_ram")
                    recommended="${recommended}kB"
                    ;;
                effective_cache_size)
                    recommended=$(pgtool_config_calc_effective_cache_size "$total_ram")
                    recommended="${recommended}kB"
                    ;;
                maintenance_work_mem)
                    recommended=$(pgtool_config_calc_maintenance_work_mem "$total_ram")
                    recommended="${recommended}kB"
                    ;;
            esac

            echo "    建议值: $recommended"
            echo "    原因: $recommendation"
            echo
        fi
    done <<< "$(pgtool_config_rules_all)"

    echo "总结: $critical_count 严重, $warning_count 警告, $info_count 信息"
    echo
}

# Show all configuration
pgtool_config_analyze_all() {
    local category="${1:-}"

    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "config" "analyze"); then
        pgtool_fatal "SQL文件未找到: config/analyze"
    fi

    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --variable="category=${category}" \
        --pset=pager=off \
        $format_args \
        2>&1
}

# Show changed configuration only
pgtool_config_analyze_changed() {
    echo "已更改的配置 (非默认值):"
    echo

    pgtool_pg_exec "SELECT name, setting, unit, boot_val, source FROM pg_settings WHERE source != 'default' ORDER BY name" \
        --pset=pager=off \
        2>/dev/null
}

# Help function
pgtool_config_analyze_help() {
    cat <<EOF
分析PostgreSQL配置

分析当前配置并提供基于最佳实践的优化建议。

用法: pgtool config analyze [选项]

选项:
  -h, --help              显示帮助
      --category CAT      按类别过滤 (memory|wal|vacuum|logging|replication)
      --changed-only      仅显示已更改的参数
      --recommend         显示优化建议
      --format FORMAT     输出格式 (table|json|csv|tsv)

建议规则:
  - shared_buffers: 25% of RAM (max 8GB)
  - effective_cache_size: 50% of RAM
  - work_mem: RAM / max_connections / 4
  - maintenance_work_mem: 1GB or 10% RAM
  - 启用SSL、自动清理、日志收集等

示例:
  pgtool config analyze
  pgtool config analyze --recommend
  pgtool config analyze --category=memory
  pgtool config analyze --changed-only
  pgtool config analyze --recommend --format=json
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/config/analyze.sh
git commit -m "feat(config): add analyze command for configuration analysis"
```

---

## Task 6: Implement Config Get Command

**Files:**
- Create: `commands/config/get.sh`

- [ ] **Step 1: Write get.sh**

```bash
#!/bin/bash
# commands/config/get.sh - Config get command

#==============================================================================
# Main function
#==============================================================================

pgtool_config_get() {
    local -a opts=()
    local -a args=()
    local param=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_get_help
                return 0
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                if [[ -z "$param" ]]; then
                    param="$1"
                fi
                args+=("$1")
                shift
                ;;
        esac
    done

    # Validate parameter name
    if [[ -z "$param" ]]; then
        pgtool_error "需要指定参数名"
        pgtool_config_get_help
        return $EXIT_INVALID_ARGS
    fi

    pgtool_info "获取参数: $param"
    echo

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Find SQL file
    local sql_file
    if ! sql_file=$(pgtool_pg_find_sql "config" "get"); then
        pgtool_fatal "SQL文件未找到: config/get"
    fi

    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --variable="name=$param" \
        --pset=pager=off \
        $format_args \
        2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_error "查询失败: $result"
        return $EXIT_SQL_ERROR
    fi

    # Check if parameter exists
    if echo "$result" | grep -q "(0 rows)"; then
        pgtool_error "参数不存在: $param"
        return $EXIT_NOT_FOUND
    fi

    echo "$result"

    # Show restart/reload requirement
    local context
    context=$(pgtool_pg_query_one "SELECT context FROM pg_settings WHERE name = '$param'" 2>/dev/null)

    echo
    case "$context" in
        postmaster)
            echo "注意: 修改此参数需要重启PostgreSQL (context: $context)"
            ;;
        sighup)
            echo "注意: 修改此参数需要执行 SELECT pg_reload_conf(); (context: $context)"
            ;;
        *)
            echo "注意: 此参数修改后即时生效 (context: $context)"
            ;;
    esac

    return $EXIT_SUCCESS
}

# Help function
pgtool_config_get_help() {
    cat <<EOF
获取配置参数值

显示指定配置参数的详细信息，包括当前值、默认值、单位和生效方式。

用法: pgtool config get <参数名> [选项]

选项:
  -h, --help              显示帮助
      --format FORMAT     输出格式 (table|json|csv|tsv)

参数上下文说明:
  internal    - 编译时设置，无法修改
  postmaster  - 需要重启PostgreSQL
  sighup      - 需要执行 pg_reload_conf()
  superuser   - 超级用户可即时修改
  user        - 会话级参数，可即时修改

示例:
  pgtool config get shared_buffers
  pgtool config get max_connections
  pgtool config get work_mem --format=json
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/config/get.sh
git commit -m "feat(config): add get command for retrieving parameter values"
```

---

## Task 7: Implement Config Set Command

**Files:**
- Create: `commands/config/set.sh`

- [ ] **Step 1: Write set.sh**

```bash
#!/bin/bash
# commands/config/set.sh - Config set command

#==============================================================================
# Main function
#==============================================================================

pgtool_config_set() {
    local -a opts=()
    local -a args=()
    local param=""
    local value=""
    local dry_run=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_set_help
                return 0
                ;;
            --param)
                shift
                param="$1"
                shift
                ;;
            --value)
                shift
                value="$1"
                shift
                ;;
            --apply)
                dry_run=false
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Validate inputs
    if [[ -z "$param" ]]; then
        pgtool_error "需要指定 --param <参数名>"
        return $EXIT_INVALID_ARGS
    fi

    if [[ -z "$value" ]]; then
        pgtool_error "需要指定 --value <值>"
        return $EXIT_INVALID_ARGS
    fi

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Check if parameter exists
    local current_value context vartype
    current_value=$(pgtool_pg_query_one "SELECT setting FROM pg_settings WHERE name = '$param'" 2>/dev/null)

    if [[ -z "$current_value" ]]; then
        pgtool_error "参数不存在: $param"
        return $EXIT_NOT_FOUND
    fi

    context=$(pgtool_pg_query_one "SELECT context FROM pg_settings WHERE name = '$param'" 2>/dev/null)
    vartype=$(pgtool_pg_query_one "SELECT vartype FROM pg_settings WHERE name = '$param'" 2>/dev/null)

    echo "参数设置:"
    echo "  名称: $param"
    echo "  当前值: $current_value"
    echo "  新值: $value"
    echo "  类型: $vartype"
    echo "  上下文: $context"
    echo

    # Validate value type
    case "$vartype" in
        bool)
            if [[ "$value" != "on" && "$value" != "off" && "$value" != "true" && "$value" != "false" ]]; then
                pgtool_error "布尔类型参数必须是 on/off/true/false"
                return $EXIT_INVALID_ARGS
            fi
            ;;
        integer)
            if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
                pgtool_error "整数类型参数必须是数字"
                return $EXIT_INVALID_ARGS
            fi
            ;;
    esac

    # Generate ALTER SYSTEM command
    local sql="ALTER SYSTEM SET $param = '$value';"

    echo "SQL命令:"
    echo "  $sql"
    echo

    case "$context" in
        postmaster)
            echo "注意: 此参数需要重启PostgreSQL才能生效"
            ;;
        sighup)
            echo "注意: 执行后需要运行: SELECT pg_reload_conf();"
            ;;
    esac
    echo

    if [[ "$dry_run" == true ]]; then
        pgtool_info "当前为 --dry-run 模式，未实际执行"
        pgtool_info "添加 --apply 选项以实际执行"
        return $EXIT_SUCCESS
    fi

    # Execute the command
    pgtool_warn "即将执行 ALTER SYSTEM..."
    echo

    local result
    result=$(pgtool_pg_exec "$sql" 2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_error "执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    pgtool_info "设置成功"
    echo "$result"

    return $EXIT_SUCCESS
}

# Help function
pgtool_config_set_help() {
    cat <<EOF
生成ALTER SYSTEM命令

生成用于修改配置参数的 ALTER SYSTEM 命令。
默认使用 --dry-run 模式，需要显式添加 --apply 才会执行。

用法: pgtool config set --param=<参数> --value=<值> [选项]

选项:
  -h, --help              显示帮助
      --param NAME        参数名称
      --value VALUE       参数值
      --apply             实际执行（默认是dry-run）

警告:
  此命令需要超级用户权限
  默认不执行，仅显示生成的SQL
  添加 --apply 才会实际执行

示例:
  pgtool config set --param=work_mem --value=256MB        # dry run
  pgtool config set --param=work_mem --value=256MB --apply
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/config/set.sh
git commit -m "feat(config): add set command for generating ALTER SYSTEM commands"
```

---

## Task 8: Implement Config Reset Command

**Files:**
- Create: `commands/config/reset.sh`

- [ ] **Step 1: Write reset.sh**

```bash
#!/bin/bash
# commands/config/reset.sh - Config reset command

#==============================================================================
# Main function
#==============================================================================

pgtool_config_reset() {
    local -a opts=()
    local -a args=()
    local param=""
    local all=false
    local dry_run=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_reset_help
                return 0
                ;;
            --param)
                shift
                param="$1"
                shift
                ;;
            --all)
                all=true
                shift
                ;;
            --apply)
                dry_run=false
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Validate inputs
    if [[ "$all" == false && -z "$param" ]]; then
        pgtool_error "需要指定 --param <参数名> 或 --all"
        return $EXIT_INVALID_ARGS
    fi

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    if [[ "$all" == true ]]; then
        pgtool_config_reset_all "$dry_run"
    else
        pgtool_config_reset_one "$param" "$dry_run"
    fi
}

# Reset single parameter
pgtool_config_reset_one() {
    local param="$1"
    local dry_run="$2"

    # Check if parameter exists
    local current_value context boot_val
    current_value=$(pgtool_pg_query_one "SELECT setting FROM pg_settings WHERE name = '$param'" 2>/dev/null)

    if [[ -z "$current_value" ]]; then
        pgtool_error "参数不存在: $param"
        return $EXIT_NOT_FOUND
    fi

    context=$(pgtool_pg_query_one "SELECT context FROM pg_settings WHERE name = '$param'" 2>/dev/null)
    boot_val=$(pgtool_pg_query_one "SELECT boot_val FROM pg_settings WHERE name = '$param'" 2>/dev/null)

    echo "重置参数:"
    echo "  名称: $param"
    echo "  当前值: $current_value"
    echo "  默认值: $boot_val"
    echo "  上下文: $context"
    echo

    local sql="ALTER SYSTEM RESET $param;"

    echo "SQL命令:"
    echo "  $sql"
    echo

    case "$context" in
        postmaster)
            echo "注意: 此参数需要重启PostgreSQL才能生效"
            ;;
        sighup)
            echo "注意: 执行后需要运行: SELECT pg_reload_conf();"
            ;;
    esac
    echo

    if [[ "$dry_run" == true ]]; then
        pgtool_info "当前为 --dry-run 模式，未实际执行"
        pgtool_info "添加 --apply 选项以实际执行"
        return $EXIT_SUCCESS
    fi

    pgtool_warn "即将执行 ALTER SYSTEM RESET..."
    echo

    local result
    result=$(pgtool_pg_exec "$sql" 2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_error "执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    pgtool_info "重置成功"
    echo "$result"
}

# Reset all parameters
pgtool_config_reset_all() {
    local dry_run="$1"

    # Get all non-default parameters
    local changed_params
    changed_params=$(pgtool_pg_exec "SELECT name FROM pg_settings WHERE source != 'default' ORDER BY name" --tuples-only --quiet 2>/dev/null | tr -d ' ')

    if [[ -z "$changed_params" ]]; then
        pgtool_info "没有需要重置的参数（所有参数均为默认值）"
        return $EXIT_SUCCESS
    fi

    local count
    count=$(echo "$changed_params" | wc -l)

    echo "将重置 $count 个已更改的参数:"
    echo "$changed_params" | head -20
    if [[ "$count" -gt 20 ]]; then
        echo "  ... 和另外 $((count - 20)) 个参数"
    fi
    echo

    local sql="ALTER SYSTEM RESET ALL;"

    echo "SQL命令:"
    echo "  $sql"
    echo
    echo "警告: 这将重置所有已更改的参数到默认值！"
    echo

    if [[ "$dry_run" == true ]]; then
        pgtool_info "当前为 --dry-run 模式，未实际执行"
        pgtool_info "添加 --apply 选项以实际执行"
        return $EXIT_SUCCESS
    fi

    pgtool_warn "即将执行 ALTER SYSTEM RESET ALL..."
    echo

    local result
    result=$(pgtool_pg_exec "$sql" 2>&1)

    if [[ $? -ne 0 ]]; then
        pgtool_error "执行失败: $result"
        return $EXIT_SQL_ERROR
    fi

    pgtool_info "重置成功"
    echo "$result"
}

# Help function
pgtool_config_reset_help() {
    cat <<EOF
生成ALTER SYSTEM RESET命令

将参数重置为默认值。
默认使用 --dry-run 模式，需要显式添加 --apply 才会执行。

用法: pgtool config reset [选项]

选项:
  -h, --help              显示帮助
      --param NAME        要重置的参数名称
      --all               重置所有已更改的参数
      --apply             实际执行（默认是dry-run）

警告:
  此命令需要超级用户权限
  --all 会重置所有已更改的参数，请谨慎使用
  默认不执行，仅显示生成的SQL

示例:
  pgtool config reset --param=work_mem              # dry run
  pgtool config reset --param=work_mem --apply
  pgtool config reset --all                         # dry run
  pgtool config reset --all --apply
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/config/reset.sh
git commit -m "feat(config): add reset command for generating ALTER SYSTEM RESET"
```

---

## Task 9: Implement Config Export Command

**Files:**
- Create: `commands/config/export.sh`

- [ ] **Step 1: Write export.sh**

```bash
#!/bin/bash
# commands/config/export.sh - Config export command

#==============================================================================
# Main function
#==============================================================================

pgtool_config_export() {
    local -a opts=()
    local -a args=()
    local category=""
    local changed_only=false
    local format="conf"  # conf, alter, json

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_export_help
                return 0
                ;;
            --category)
                shift
                category="$1"
                shift
                ;;
            --changed-only)
                changed_only=true
                shift
                ;;
            --format)
                shift
                format="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level|--host|--port|--user|--dbname)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    pgtool_info "导出配置..."
    echo

    # Test connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    case "$format" in
        conf)
            pgtool_config_export_conf "$category" "$changed_only"
            ;;
        alter|sql)
            pgtool_config_export_alter "$category" "$changed_only"
            ;;
        json)
            pgtool_config_export_json "$category" "$changed_only"
            ;;
        *)
            pgtool_error "未知格式: $format (支持: conf, alter, json)"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

# Export to postgresql.conf format
pgtool_config_export_conf() {
    local category="$1"
    local changed_only="$2"

    local sql
    sql="SELECT '# ' || short_desc || E'\n' || name || ' = ' || setting FROM pg_settings WHERE 1=1"

    if [[ "$changed_only" == true ]]; then
        sql="$sql AND source != 'default'"
    fi

    if [[ -n "$category" ]]; then
        sql="$sql AND category ILIKE '%$category%'"
    fi

    sql="$sql ORDER BY category, name"

    echo "# PostgreSQL configuration export"
    echo "# Generated: $(date)"
    echo "# Database: $PGTOOL_DATABASE"
    echo "# Host: $PGTOOL_HOST:$PGTOOL_PORT"
    echo

    pgtool_pg_exec "$sql" --tuples-only --quiet 2>/dev/null
}

# Export to ALTER SYSTEM format
pgtool_config_export_alter() {
    local category="$1"
    local changed_only="$2"

    local sql
    sql="SELECT 'ALTER SYSTEM SET ' || name || ' = ''' || setting || ''';' FROM pg_settings WHERE 1=1"

    if [[ "$changed_only" == true ]]; then
        sql="$sql AND source != 'default'"
    fi

    if [[ -n "$category" ]]; then
        sql="$sql AND category ILIKE '%$category%'"
    fi

    sql="$sql ORDER BY name"

    echo "-- PostgreSQL ALTER SYSTEM export"
    echo "-- Generated: $(date)"
    echo "-- Database: $PGTOOL_DATABASE"
    echo "--"
    echo "-- Apply with:"
    echo "--   psql -c \"$(cat)\""
    echo "-- Then reload:"
    echo "--   SELECT pg_reload_conf();"
    echo

    pgtool_pg_exec "$sql" --tuples-only --quiet 2>/dev/null
}

# Export to JSON format
pgtool_config_export_json() {
    local category="$1"
    local changed_only="$2"

    local where_clause="WHERE category != 'Custom Variable Classes'"

    if [[ "$changed_only" == true ]]; then
        where_clause="$where_clause AND source != 'default'"
    fi

    if [[ -n "$category" ]]; then
        where_clause="$where_clause AND category ILIKE '%$category%'"
    fi

    echo "{"
    echo "  \"exported_at\": \"$(date -Iseconds)\","
    echo "  \"database\": \"$PGTOOL_DATABASE\","
    echo "  \"host\": \"$PGTOOL_HOST\","
    echo "  \"port\": $PGTOOL_PORT,"
    echo "  \"settings\": ["

    local first=true
    local row
    while IFS='|' read -r name setting unit source; do
        [[ -z "$name" ]] && continue

        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi

        echo -n "    {\"name\": \"$name\", \"value\": \"$setting\", \"unit\": \"$unit\", \"source\": \"$source\"}"
    done <<< "$(pgtool_pg_exec "SELECT name, setting, COALESCE(unit, ''), source FROM pg_settings $where_clause ORDER BY name" --pset=format=unaligned --pset=fieldsep='|' --tuples-only --quiet 2>/dev/null)"

    echo
    echo "  ]"
    echo "}"
}

# Help function
pgtool_config_export_help() {
    cat <<EOF
导出配置

导出配置参数到多种格式。

用法: pgtool config export [选项]

选项:
  -h, --help              显示帮助
      --category CAT      按类别过滤
      --changed-only      仅导出已更改的参数
      --format FORMAT     输出格式 (conf|alter|json)

格式说明:
  conf   - postgresql.conf 格式（默认）
  alter  - ALTER SYSTEM SQL 格式
  json   - JSON 格式

示例:
  pgtool config export
  pgtool config export --changed-only
  pgtool config export --category=memory --format=json
  pgtool config export --format=alter > config.sql
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/config/export.sh
git commit -m "feat(config): add export command for configuration export"
```

---

## Task 10: Implement Config Diff Command

**Files:**
- Create: `commands/config/diff.sh`

- [ ] **Step 1: Write diff.sh**

```bash
#!/bin/bash
# commands/config/diff.sh - Config diff command

#==============================================================================
# Main function
#==============================================================================

pgtool_config_diff() {
    local -a opts=()
    local -a args=()
    local target_host=""
    local target_port=""
    local target_db=""
    local target_user=""
    local category=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                pgtool_config_diff_help
                return 0
                ;;
            --target-host)
                shift
                target_host="$1"
                shift
                ;;
            --target-port)
                shift
                target_port="$1"
                shift
                ;;
            --target-db)
                shift
                target_db="$1"
                shift
                ;;
            --target-user)
                shift
                target_user="$1"
                shift
                ;;
            --category)
                shift
                category="$1"
                shift
                ;;
            --format)
                shift
                PGTOOL_FORMAT="$1"
                shift
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            --timeout|--color|--log-level)
                shift
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Validate target
    if [[ -z "$target_host" ]]; then
        pgtool_error "需要指定 --target-host <主机>"
        return $EXIT_INVALID_ARGS
    fi

    target_port="${target_port:-5432}"
    target_db="${target_db:-$PGTOOL_DATABASE}"
    target_user="${target_user:-$PGTOOL_USER}"

    pgtool_info "比较配置差异..."
    echo "  源: $PGTOOL_HOST:$PGTOOL_PORT/$PGTOOL_DATABASE"
    echo "  目标: $target_host:$target_port/$target_db"
    echo

    # Test source connection
    if ! pgtool_pg_test_connection; then
        return $EXIT_CONNECTION_ERROR
    fi

    # Get source config
    local source_config
    source_config=$(pgtool_config_diff_get_config "$PGTOOL_HOST" "$PGTOOL_PORT" "$PGTOOL_DATABASE" "$PGTOOL_USER" "$category")

    if [[ $? -ne 0 ]]; then
        pgtool_error "无法获取源配置"
        return $EXIT_CONNECTION_ERROR
    fi

    # Get target config
    local target_config
    target_config=$(pgtool_config_diff_get_config "$target_host" "$target_port" "$target_db" "$target_user" "$category")

    if [[ $? -ne 0 ]]; then
        pgtool_error "无法获取目标配置"
        return $EXIT_CONNECTION_ERROR
    fi

    # Compare and display
    pgtool_config_diff_compare "$source_config" "$target_config"
}

# Get config from a database
pgtool_config_diff_get_config() {
    local host="$1"
    local port="$2"
    local db="$3"
    local user="$4"
    local category="$5"

    local where_clause="WHERE source != 'default'"

    if [[ -n "$category" ]]; then
        where_clause="$where_clause AND category ILIKE '%$category%'"
    fi

    timeout "$PGTOOL_TIMEOUT" psql \
        --host="$host" \
        --port="$port" \
        --dbname="$db" \
        --username="$user" \
        --no-psqlrc \
        --no-align \
        --tuples-only \
        --quiet \
        --command="SELECT name, setting FROM pg_settings $where_clause ORDER BY name" \
        2>/dev/null
}

# Compare configs
pgtool_config_diff_compare() {
    local source="$1"
    local target="$2"

    echo "配置差异:"
    echo "========="
    echo

    local found_diff=false

    # Build associative arrays for comparison
    declare -A source_values
    declare -A target_values

    while IFS='|' read -r name value; do
        [[ -z "$name" ]] && continue
        source_values["$name"]="$value"
    done <<< "$source"

    while IFS='|' read -r name value; do
        [[ -z "$name" ]] && continue
        target_values["$name"]="$value"
    done <<< "$target"

    # Find differences
    for name in "${!source_values[@]}"; do
        local source_val="${source_values[$name]}"
        local target_val="${target_values[$name]:-NOTSET}"

        if [[ "$source_val" != "$target_val" ]]; then
            found_diff=true
            echo "  $name:"
            echo "    源:   $source_val"
            echo "    目标: $target_val"
            echo
        fi
    done

    # Find settings only in target
    for name in "${!target_values[@]}"; do
        if [[ -z "${source_values[$name]:-}" ]]; then
            found_diff=true
            echo "  $name:"
            echo "    源:   (未设置)"
            echo "    目标: ${target_values[$name]}"
            echo
        fi
    done

    if [[ "$found_diff" == false ]]; then
        echo "  配置相同，无差异"
    fi
}

# Help function
pgtool_config_diff_help() {
    cat <<EOF
比较配置差异

比较两个PostgreSQL实例的配置参数差异。

用法: pgtool config diff --target-host=<主机> [选项]

选项:
  -h, --help                   显示帮助
      --target-host HOST       目标主机（必需）
      --target-port PORT       目标端口（默认: 5432）
      --target-db NAME         目标数据库（默认: 当前）
      --target-user NAME       目标用户（默认: 当前）
      --category CAT           按类别过滤
      --format FORMAT          输出格式

示例:
  pgtool config diff --target-host=prod-db.example.com
  pgtool config diff --target-host=slave --target-port=5433
  pgtool config diff --target-host=prod --category=memory
EOF
}
```

- [ ] **Step 2: Commit**

```bash
git add commands/config/diff.sh
git commit -m "feat(config): add diff command for comparing configurations"
```

---

## Task 11: Register Config Command Group

**Files:**
- Modify: `lib/cli.sh`

- [ ] **Step 1: Add config to PGTOOL_GROUPS**

```bash
# Line 15: Change from:
PGTOOL_GROUPS=("check" "stat" "admin" "analyze" "plugin")
# To:
PGTOOL_GROUPS=("check" "stat" "admin" "analyze" "plugin" "config")
```

- [ ] **Step 2: Add config case to pgtool_group_desc**

```bash
# Add before *) case:
        config)  echo "配置管理 - 分析与优化配置参数" ;;
```

- [ ] **Step 3: Commit**

```bash
git add lib/cli.sh
git commit -m "feat(config): register config command group in CLI dispatcher"
```

---

## Task 12: Create Tests

**Files:**
- Create: `tests/test_config.sh`

- [ ] **Step 1: Write test file**

```bash
#!/bin/bash
# tests/test_config.sh - Config module tests

# Load test framework
source "$TEST_DIR/test_runner.sh"

#==============================================================================
# Setup
#==============================================================================

setup_config_tests() {
    if ! type pgtool_config_detect_memory &>/dev/null; then
        source "$PGTOOL_ROOT/lib/config.sh" 2>/dev/null || true
        source "$PGTOOL_ROOT/lib/config_rules.sh" 2>/dev/null || true
    fi
}

#==============================================================================
# Tests
#==============================================================================

test_config_lib_loaded() {
    assert_true "type pgtool_config_detect_memory &>/dev/null"
    assert_true "type pgtool_config_detect_cpus &>/dev/null"
    assert_true "type pgtool_config_rules_all &>/dev/null"
}

test_config_parse_value() {
    local result

    result=$(pgtool_config_parse_value "256MB")
    assert_equals "268435456" "$result"

    result=$(pgtool_config_parse_value "1GB")
    assert_equals "1073741824" "$result"

    result=$(pgtool_config_parse_value "1024")
    assert_equals "1024" "$result"
}

test_config_format_bytes() {
    local result

    result=$(pgtool_config_format_bytes "268435456")
    assert_contains "$result" "256MB"

    result=$(pgtool_config_format_bytes "1073741824")
    assert_contains "$result" "1GB"
}

test_config_commands_exist() {
    assert_true "[[ -f $PGTOOL_ROOT/commands/config/index.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/config/analyze.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/config/diff.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/config/get.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/config/set.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/config/reset.sh ]]"
    assert_true "[[ -f $PGTOOL_ROOT/commands/config/export.sh ]]"
}

test_config_sql_files_exist() {
    assert_true "[[ -f $PGTOOL_ROOT/sql/config/analyze.sql ]]"
    assert_true "[[ -f $PGTOOL_ROOT/sql/config/get.sql ]]"
}

test_config_registered_in_cli() {
    assert_contains "${PGTOOL_GROUPS[*]}" "config"
}

test_config_rules_memory() {
    local rules
    rules=$(pgtool_config_rules_memory)
    assert_contains "$rules" "shared_buffers"
    assert_contains "$rules" "effective_cache_size"
}

#==============================================================================
# Run tests
#==============================================================================

setup_config_tests
run_test "config_lib_loaded" test_config_lib_loaded
run_test "config_parse_value" test_config_parse_value
run_test "config_format_bytes" test_config_format_bytes
run_test "config_commands_exist" test_config_commands_exist
run_test "config_sql_files_exist" test_config_sql_files_exist
run_test "config_registered" test_config_registered_in_cli
run_test "config_rules_memory" test_config_rules_memory
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_config.sh
git commit -m "test(config): add unit tests for config command group"
```

---

## Spec Coverage Check

| Requirement | Task | Status |
|-------------|------|--------|
| Config analysis with recommendations | Tasks 1, 5 | ✓ |
| System resource detection | Task 2 | ✓ |
| Best practice rules | Task 1 | ✓ |
| Config diff | Task 10 | ✓ |
| Config get | Task 6 | ✓ |
| Config set (dry-run) | Task 7 | ✓ |
| Config reset | Task 8 | ✓ |
| Config export | Task 9 | ✓ |
| Category filtering | Multiple | ✓ |
| Command registration | Task 11 | ✓ |
| Tests | Task 12 | ✓ |

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-02-config-command-group.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
