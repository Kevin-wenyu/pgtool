# Implementation Plan: pgtool config command group

## Task Type
- [x] Backend (→ Codex)
- [ ] Frontend (→ Gemini)
- [ ] Fullstack (→ Parallel)

## Overview
Add a new `config` command group to pgtool for PostgreSQL configuration management and optimization. This provides DBAs with tools to analyze configuration, compare with best practices, and generate optimization recommendations.

## Technical Solution

### Architecture
1. **New command group**: `commands/config/` directory
2. **Configuration analysis**: Query pg_settings and analyze values
3. **Best practice rules**: Embedded recommendations based on PG version
4. **Optimization engine**: Calculate optimal values based on system resources
5. **Reporting**: Generate configuration reports with recommendations

### Commands
1. `config analyze` - Analyze current configuration and show recommendations
2. `config diff` - Compare configuration between two instances
3. `config get` - Get specific configuration parameter value
4. `config set` - Generate ALTER SYSTEM commands (with --dry-run)
5. `config reset` - Show commands to reset parameters to defaults
6. `config export` - Export configuration to file

### Options
- `--category CAT` - Filter by category (memory, replication, logging, etc.)
- `--changed-only` - Show only changed from defaults
- `--recommend` - Show optimization recommendations
- `--format` - Output format (table, json)
- All standard global options

## Implementation Steps

### Step 1: Create command group infrastructure
**File**: `commands/config/index.sh`
```bash
PGTOOL_CONFIG_COMMANDS="analyze:分析配置并提供建议,diff:比较配置差异,get:获取参数值,set:生成设置命令,reset:显示重置命令,export:导出配置"

pgtool_config_help() {
    # Help text for config commands
}
```

### Step 2: Add config to CLI dispatcher
**File**: `lib/cli.sh:L15`
- Add "config" to `PGTOOL_GROUPS` array
- Add "config" case to `pgtool_group_desc()`

### Step 3: Create config utilities library
**File**: `lib/config.sh`
```bash
# Configuration retrieval
pgtool_config_get_all()              # Get all configuration parameters
pgtool_config_get_param()            # Get specific parameter value
pgtool_config_get_changed()          # Get only changed parameters

# Configuration analysis
pgtool_config_analyze_memory()       # Analyze memory-related settings
pgtool_config_analyze_replication()  # Analyze replication settings
pgtool_config_analyze_logging()      # Analyze logging settings
pgtool_config_analyze_vacuum()       # Analyze autovacuum settings
pgtool_config_analyze_wal()          # Analyze WAL settings

# Best practice rules
pgtool_config_check_rule()           # Check parameter against rule
pgtool_config_get_recommendation()   # Get recommendation for parameter

# System resource detection
pgtool_config_detect_memory()        # Detect system memory
pgtool_config_detect_cpus()          # Detect CPU count
pgtool_config_detect_disk()          # Detect disk type (SSD/HDD)

# Optimization calculation
pgtool_config_calc_shared_buffers()  # Calculate optimal shared_buffers
pgtool_config_calc_effective_cache_size()  # Calculate effective_cache_size
pgtool_config_calc_work_mem()        # Calculate optimal work_mem
pgtool_config_calc_maintenance_work_mem()  # Calculate maintenance_work_mem

# Formatting
pgtool_config_format_value()         # Format config value with units
pgtool_config_format_recommendation() # Format recommendation output
```

### Step 4: Create best practices rules
**File**: `lib/config_rules.sh`
```bash
# Rule format: name|category|check_type|threshold|recommendation|severity

# Memory rules
pgtool_config_rules_memory() {
    cat <<'RULES'
shared_buffers|memory|percent_of_ram|25|Set to 25% of RAM|warning
effective_cache_size|memory|percent_of_ram|50|Set to 50% of RAM|warning
work_mem|memory|formula|total_ram/max_connections/4|Based on workload|info
maintenance_work_mem|memory|min|1GB|Set at least 1GB for maintenance|warning
RULES
}

# Connection rules
pgtool_config_rules_connections() {
    cat <<'RULES'
max_connections|connections|max|500|Consider using connection pooler|warning
RULES
}

# WAL rules
pgtool_config_rules_wal() {
    cat <<'RULES'
wal_buffers|wal|auto|-1|Keep at -1 (auto)|info
min_wal_size|wal|min|1GB|Set at least 1GB|warning
max_wal_size|wal|min|4GB|Set at least 4GB|warning
RULES
}

# Vacuum rules
pgtool_config_rules_vacuum() {
    cat <<'RULES'
autovacuum|vacuum|value|on|Keep autovacuum enabled|critical
autovacuum_max_workers|vacuum|min|3|Set at least 3 workers|warning
autovacuum_naptime|vacuum|max|60|Set to 60s or less|warning
RULES
}

# Replication rules
pgtool_config_rules_replication() {
    cat <<'RULES'
wal_level|replication|value|replica|Set wal_level to replica or higher|critical
max_wal_senders|replication|min|2|Set at least 2 for replication|warning
hot_standby|replication|value|on|Enable hot_standby for replicas|warning
RULES
}
```

### Step 5: Implement config analyze command
**File**: `commands/config/analyze.sh`

```bash
pgtool_config_analyze() {
    # Parse options: --category, --changed-only, --recommend
    # Query pg_settings for all parameters
    # For each parameter:
        # Check against best practice rules
        # Calculate recommendations based on system resources
        # Flag issues by severity (critical, warning, info)
    # Output formatted report with:
        # Current value
        # Recommended value
        # Reason
        # ALTER SYSTEM command to apply
}
```

**File**: `sql/config/analyze.sql`
```sql
SELECT
    name,
    setting,
    unit,
    context,
    vartype,
    source,
    boot_val as default_value,
    category,
    short_desc
FROM pg_settings
WHERE category != 'Custom Variable Classes'
ORDER BY category, name;
```

### Step 6: Implement config diff command
**File**: `commands/config/diff.sh`
```bash
pgtool_config_diff() {
    # Parse options: --target-host, --target-port, --target-db
    # Get configuration from current database
    # Get configuration from target database
    # Compare and show:
        # Parameters that differ
        # Current value vs target value
        # Recommendation to align
}
```

### Step 7: Implement config get command
**File**: `commands/config/get.sh`
```bash
pgtool_config_get() {
    # Parse parameter name from args
    # Query pg_settings for specific parameter
    # Show detailed info:
        # Current value
        # Default value
        # Unit
        # Context (when change takes effect)
        # Description
}
```

**File**: `sql/config/get.sql`
```sql
SELECT
    name,
    setting,
    unit,
    context,
    vartype,
    boot_val as default_value,
    category,
    short_desc,
    extra_desc
FROM pg_settings
WHERE name = :param_name;
```

### Step 8: Implement config set command
**File**: `commands/config/set.sh`
```bash
pgtool_config_set() {
    # Parse: --param NAME --value VALUE [--dry-run]
    # Validate parameter exists
    # Validate value is valid for parameter type
    # Generate ALTER SYSTEM command
    # If not --dry-run, execute after confirmation
    # Show reload/restart requirement
}
```

### Step 9: Implement config reset command
**File**: `commands/config/reset.sh`
```bash
pgtool_config_reset() {
    # Parse: --param NAME or --all
    # Generate ALTER SYSTEM RESET command(s)
    # Show which parameters will be affected
    # Show reload/restart requirement
}
```

### Step 10: Implement config export command
**File**: `commands/config/export.sh`
```bash
pgtool_config_export() {
    # Parse options: --category, --changed-only
    # Query configuration
    # Export to file:
        # postgresql.conf format
        # JSON format (if --format=json)
        # SQL format (ALTER SYSTEM commands)
}
```

### Step 11: Create SQL templates
**Files**: `sql/config/*.sql`

`sql/config/analyze.sql` - Full configuration query
`sql/config/get.sql` - Single parameter query
`sql/config/changed.sql` - Changed from defaults

### Step 12: Test implementation
- Test on different PostgreSQL versions (12-17)
- Test with different memory sizes
- Test changed-only filtering
- Test category filtering
- Test recommendation accuracy

## Key Files

| File | Operation | Description |
|------|-----------|-------------|
| `commands/config/index.sh` | Create | Command group index |
| `commands/config/analyze.sh` | Create | Config analyze command |
| `commands/config/diff.sh` | Create | Config diff command |
| `commands/config/get.sh` | Create | Config get command |
| `commands/config/set.sh` | Create | Config set command |
| `commands/config/reset.sh` | Create | Config reset command |
| `commands/config/export.sh` | Create | Config export command |
| `lib/config.sh` | Create | Config utility functions |
| `lib/config_rules.sh` | Create | Best practice rules |
| `lib/cli.sh:L15` | Modify | Add "config" to PGTOOL_GROUPS |
| `sql/config/analyze.sql` | Create | Configuration query SQL |
| `sql/config/get.sql` | Create | Single parameter SQL |
| `sql/config/changed.sql` | Create | Changed parameters SQL |

## Risks and Mitigation

| Risk | Mitigation |
|------|------------|
| Recommendations not suitable for all workloads | Add disclaimer, allow custom rule files |
| Version-specific parameters | Detect PG version and adjust rules |
| Wrong calculations for memory | Use proper units (kB, MB, GB) |
| ALTER SYSTEM requires restart | Show clear restart/reload requirements |
| Permission to alter system | Check permissions before executing |

## Pseudo-code

```bash
# lib/config.sh
pgtool_config_analyze_memory() {
    local total_ram=$(pgtool_config_detect_memory)
    local shared_buffers=$(pgtool_config_get_param "shared_buffers")
    local recommended=$((total_ram / 4))

    if [[ $shared_buffers -lt $recommended ]]; then
        echo "WARNING: shared_buffers is low"
        echo "Current: $shared_buffers"
        echo "Recommended: ${recommended}kB (25% of RAM)"
        echo "Command: ALTER SYSTEM SET shared_buffers = '${recommended}kB';"
    fi
}

pgtool_config_detect_memory() {
    # Try to detect system memory in kB
    if [[ -f /proc/meminfo ]]; then
        awk '/MemTotal/{print $2}' /proc/meminfo
    elif command -v sysctl &>/dev/null; then
        sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024}'
    else
        # Fallback to PostgreSQL's view
        pgtool_pg_query_one "SELECT pg_total_memory() / 1024"
    fi
}
```

## SESSION_ID
- CODEX_SESSION: N/A (local planning)
- GEMINI_SESSION: N/A (local planning)
