# pgtool Command Group Implementation Plans - Summary

Created: 2026-04-02

## Overview

Four new command groups planned for pgtool to expand its PostgreSQL administration capabilities:

| Command Group | Commands | Complexity | Priority |
|---------------|----------|------------|----------|
| **monitor** | 3 (queries, connections, replication) | Medium | High |
| **backup** | 5 (status, verify, archive, list, info) | High | High |
| **config** | 6 (analyze, diff, get, set, reset, export) | High | Medium |
| **user** | 6 (list, info, permissions, activity, audit, tree) | Medium | Medium |

**Total: 20 new commands**

---

## Plan Files

1. **`2026-04-02-monitor-command-group.md`** - Real-time monitoring (like `top`)
   - Interactive terminal UI with ANSI escape sequences
   - Color coding for dangerous states
   - --once mode for scripting

2. **`2026-04-02-backup-command-group.md`** - Backup management
   - pgBackRest/Barman/pg_dump integration
   - Auto-detect backup tools
   - WAL archiving status

3. **`2026-04-02-config-command-group.md`** - Configuration analysis
   - Best practice rules based on PG version
   - System resource detection (RAM, CPU)
   - Generates ALTER SYSTEM commands (dry-run by default)

4. **`2026-04-02-user-command-group.md`** - User/permission management
   - Read-only security audit
   - Role membership tree visualization
   - Permission analysis

---

## Implementation Order Recommendation

### Phase 1: High Impact, Lower Complexity
1. **user** - Pure SQL queries, no external dependencies
2. **monitor** - Standalone commands with --once mode for testing

### Phase 2: External Tool Integration
3. **backup** - Requires pgBackRest/Barman for full testing
4. **config** - Complex rule engine, system resource detection

---

## Execution Options

### Option 1: Subagent-Driven (Recommended)
- Spawn fresh subagent per task
- Review between tasks
- Parallelize independent tasks
- Best for quality control

### Option 2: Inline Execution
- Execute in this session
- Batch execution with checkpoints
- Faster but requires more attention

---

## Files to be Created

```
commands/
├── monitor/
│   ├── index.sh
│   ├── queries.sh
│   ├── connections.sh
│   └── replication.sh
├── backup/
│   ├── index.sh
│   ├── status.sh
│   ├── verify.sh
│   ├── archive.sh
│   ├── list.sh
│   └── info.sh
├── config/
│   ├── index.sh
│   ├── analyze.sh
│   ├── diff.sh
│   ├── get.sh
│   ├── set.sh
│   ├── reset.sh
│   └── export.sh
└── user/
    ├── index.sh
    ├── list.sh
    ├── info.sh
    ├── permissions.sh
    ├── activity.sh
    ├── audit.sh
    └── tree.sh

lib/
├── monitor.sh
├── backup.sh
├── config.sh
├── config_rules.sh
└── user.sh

sql/
├── monitor/
│   ├── queries.sql
│   ├── connections.sql
│   └── replication.sql
├── backup/
│   └── archive.sql
├── config/
│   ├── analyze.sql
│   └── get.sql
└── user/
    ├── list.sql
    ├── info.sql
    ├── activity.sql
    ├── permissions_database.sql
    ├── permissions_tables.sql
    ├── audit_superusers.sql
    └── membership.sql

tests/
├── test_monitor.sh
├── test_backup.sh
├── test_config.sh
└── test_user.sh
```

---

## Key Architecture Decisions

1. **SQL Separation** - All SQL queries in dedicated `sql/` files
2. **Library Modules** - Each command group has its own `lib/<group>.sh`
3. **Consistent CLI** - All commands follow same option parsing pattern
4. **Read-Only by Default** - Dangerous commands (set, reset) use --dry-run default
5. **Auto-Detection** - Backup tools and system resources auto-detected

---

## Testing Strategy

- Unit tests for library functions
- File existence tests for all new files
- Integration tests where possible
- Skip tests when dependencies unavailable

---

## Next Steps

1. Choose execution approach (subagent vs inline)
2. Select command group order
3. Begin Task 1 of first command group
4. Review and commit after each task
