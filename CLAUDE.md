# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

pgtool is a PostgreSQL CLI toolkit inspired by kubectl. It's a bash-based tool providing 19+ commands for PostgreSQL administration, monitoring, and analysis. The architecture uses a modular plugin system with SQL file separation.

## Architecture

### Directory Structure

```
pgtool/
├── pgtool.sh              # Main entry point - parses global options, loads libs, dispatches commands
├── lib/                   # Core library modules (sourced by pgtool.sh)
│   ├── core.sh           # Constants, exit codes, initialization
│   ├── cli.sh            # Command dispatcher, global option parsing
│   ├── log.sh            # Logging utilities (pgtool_info, pgtool_warn, pgtool_error, pgtool_fatal)
│   ├── pg.sh             # PostgreSQL connection management, SQL execution
│   ├── output.sh         # Output formatting (table, json, csv, tsv)
│   ├── util.sh           # General utility functions
│   └── plugin.sh         # Plugin loader
├── commands/              # Built-in command implementations
│   ├── check/            # Health check commands (xid, replication, autovacuum, connection)
│   ├── stat/             # Statistics commands (activity, locks, database, table, indexes)
│   ├── admin/            # Administrative commands (kill-blocking, cancel-query, checkpoint, reload)
│   ├── analyze/          # Analysis commands (bloat, missing-indexes, slow-queries, vacuum-stats)
│   └── plugin/           # Plugin management commands
├── sql/                   # SQL query templates organized by command group
│   ├── check/
│   ├── stat/
│   ├── admin/
│   └── analyze/
├── plugins/               # External plugin directory (user-extensible)
├── conf/                  # Configuration templates
└── tests/                 # Test suite
```

### Command Execution Flow

1. **pgtool.sh** parses global options (`--config`, `--format`, `--timeout`, connection params)
2. **lib/cli.sh** `pgtool_dispatch()` identifies command group and command
3. Load command group index from `commands/<group>/index.sh`
4. Load specific command from `commands/<group>/<command>.sh`
5. Execute `pgtool_<group>_<command>()` function

### Key Architectural Patterns

- **Command Registration**: Each command group has an `index.sh` that defines `PGTOOL_<GROUP>_COMMANDS` variable (comma-separated list of `command:description`)
- **SQL Separation**: SQL files live in `sql/<group>/<command>.sql`, loaded via `pgtool_pg_find_sql()` and executed via `pgtool_exec_sql_file()`
- **Plugin System**: External plugins in `plugins/<name>/` with `plugin.conf` and `commands/` subdirectory
- **Exit Codes**: Defined in `lib/core.sh` - SUCCESS=0, GENERAL_ERROR=1, INVALID_ARGS=2, CONNECTION_ERROR=3, TIMEOUT=4, SQL_ERROR=5, NOT_FOUND=6, PERMISSION=7

## Common Commands

### Build/Install

```bash
# Install to system (default: /usr/local)
./install.sh

# Install to custom prefix
./install.sh --prefix=$HOME/.local
```

### Testing

```bash
# Run all tests
cd tests && ./run.sh

# Run specific test file
./run.sh test_util
./run.sh test_core
./run.sh test_cli
./run.sh test_commands
./run.sh test_pg
./run.sh test_plugin

# Run with test runner directly
bash tests/test_runner.sh
```

### Running the Tool

```bash
# During development (use ./pgtool.sh directly)
./pgtool.sh --help
./pgtool.sh check xid
./pgtool.sh stat activity --format=json

# With custom config
./pgtool.sh --config ./.pgtool.conf check xid
```

## Configuration

Config files are searched in this priority order:
1. `--config <file>` argument
2. `$PGTOOL_CONFIG` environment variable
3. `./.pgtool.conf` (current directory)
4. `$HOME/.config/pgtool/pgtool.conf`
5. `$HOME/.pgtool.conf`
6. `/etc/pgtool/pgtool.conf`

Connection can also be configured via standard PostgreSQL environment variables: `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, `PGPASSWORD`.

## Adding a New Command

1. Create SQL file at `sql/<group>/<command>.sql`
2. Create command script at `commands/<group>/<command>.sh` with function `pgtool_<group>_<command>()`
3. Register in `commands/<group>/index.sh` by adding to `PGTOOL_<GROUP>_COMMANDS`

## Testing Framework

Tests use a custom framework in `tests/test_runner.sh` with these assertions:
- `assert_equals expected actual`
- `assert_true value`
- `assert_false value`
- `assert_not_empty value`
- `assert_empty value`
- `assert_contains string substring`

Skip tests with `skip_test "reason"` when dependencies unavailable.
