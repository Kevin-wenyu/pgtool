#!/bin/bash
# lib/pg.sh - PostgreSQL 连接与执行封装

# 必须先加载 core.sh 和 log.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# 连接配置
#==============================================================================

# 连接选项数组
PGTOOL_CONN_OPTS=()

# 初始化连接选项
pgtool_pg_init() {
    PGTOOL_CONN_OPTS=()

    # 从环境变量或配置构建连接选项
    local host="${PGHOST:-${PGTOOL_HOST:-localhost}}"
    local port="${PGPORT:-${PGTOOL_PORT:-5432}}"
    local user="${PGUSER:-${PGTOOL_USER:-$USER}}"
    local dbname="${PGDATABASE:-${PGTOOL_DATABASE:-postgres}}"

    PGTOOL_CONN_OPTS+=("--host=$host")
    PGTOOL_CONN_OPTS+=("--port=$port")
    PGTOOL_CONN_OPTS+=("--username=$user")
    PGTOOL_CONN_OPTS+=("--dbname=$dbname")

    # 非交互模式
    PGTOOL_CONN_OPTS+=("--no-psqlrc")
    PGTOOL_CONN_OPTS+=("--no-align")

    export PGTOOL_HOST="$host"
    export PGTOOL_PORT="$port"
    export PGTOOL_USER="$user"
    export PGTOOL_DATABASE="$dbname"
}

#==============================================================================
# 连接测试
#==============================================================================

# 测试数据库连接
pgtool_pg_test_connection() {
    local timeout="${1:-${PGTOOL_TIMEOUT}}"

    pgtool_debug "测试连接: $PGTOOL_HOST:$PGTOOL_PORT/$PGTOOL_DATABASE"

    if ! timeout "$timeout" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --command="SELECT 1" \
        --tuples-only \
        --quiet 2>/dev/null; then
        pgtool_error "无法连接到数据库"
        pgtool_info "连接参数: host=$PGTOOL_HOST port=$PGTOOL_PORT db=$PGTOOL_DATABASE user=$PGTOOL_USER"
        return $EXIT_CONNECTION_ERROR
    fi

    pgtool_debug "连接成功"
    return $EXIT_SUCCESS
}

# 获取数据库版本
pgtool_pg_version() {
    local version
    version=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --command="SELECT version()" \
        --tuples-only \
        --quiet 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        return $EXIT_CONNECTION_ERROR
    fi

    echo "$version"
}

# 检查是否为超级用户
pgtool_pg_is_superuser() {
    local result
    result=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --command="SELECT pg_catalog.pg_has_role(current_user, 'pg_execute_server_program', 'MEMBER') OR usesuper FROM pg_user WHERE usename = current_user" \
        --tuples-only \
        --quiet 2>/dev/null | tr -d ' ')

    [[ "$result" == "t" ]] || [[ "$result" == "true" ]]
}

#==============================================================================
# SQL 执行
#==============================================================================

# 执行 SQL 语句
pgtool_pg_exec() {
    local sql="$1"
    shift
    local format_args
    format_args=$(pgtool_pset_args "${PGTOOL_FORMAT}")

    pgtool_debug "执行 SQL: ${sql:0:100}..."

    local output
    output=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --command="$sql" \
        --pset=pager=off \
        --quiet \
        "$@" 2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $output"
        return $EXIT_SQL_ERROR
    fi

    echo "$output"
}

# 从文件执行 SQL
pgtool_pg_exec_file() {
    local sql_file="$1"
    shift

    if [[ ! -f "$sql_file" ]]; then
        pgtool_error "SQL 文件不存在: $sql_file"
        return $EXIT_NOT_FOUND
    fi

    if [[ ! -r "$sql_file" ]]; then
        pgtool_error "无法读取 SQL 文件: $sql_file"
        return $EXIT_PERMISSION
    fi

    pgtool_debug "执行 SQL 文件: $sql_file"

    local output
    output=$(timeout "$PGTOOL_TIMEOUT" psql \
        "${PGTOOL_CONN_OPTS[@]}" \
        --file="$sql_file" \
        --pset=pager=off \
        --quiet \
        "$@" 2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 124 ]]; then
        pgtool_error "SQL 执行超时 (${PGTOOL_TIMEOUT}s)"
        return $EXIT_TIMEOUT
    elif [[ $exit_code -ne 0 ]]; then
        pgtool_error "SQL 执行失败: $output"
        return $EXIT_SQL_ERROR
    fi

    echo "$output"
}

# 执行查询并获取第一行第一列
pgtool_pg_query_one() {
    local sql="$1"
    local result

    result=$(pgtool_pg_exec "$sql" --tuples-only --quiet)

    if [[ $? -ne 0 ]]; then
        return $?
    fi

    echo "$result" | head -n 1 | tr -d ' '
}

#==============================================================================
# 结果处理
#==============================================================================

# 检查结果是否为空
pgtool_pg_is_empty() {
    local result="$1"
    [[ -z "$result" ]] || [[ "$result" == "(0 rows)" ]] || [[ "$result" == "NULL" ]]
}

# 获取结果行数
pgtool_pg_row_count() {
    local result="$1"
    echo "$result" | grep -c '^' 2>/dev/null || echo 0
}

#==============================================================================
# SQL 文件管理
#==============================================================================

# 查找 SQL 文件
pgtool_pg_find_sql() {
    local group="$1"
    local command="$2"
    local sql_file="$PGTOOL_ROOT/sql/$group/$command.sql"

    if [[ -f "$sql_file" ]]; then
        echo "$sql_file"
        return 0
    fi

    return 1
}

# 加载 SQL 文件内容
pgtool_pg_load_sql() {
    local group="$1"
    local command="$2"
    local sql_file

    if ! sql_file=$(pgtool_pg_find_sql "$group" "$command"); then
        pgtool_error "未找到 SQL 文件: $group/$command"
        return $EXIT_NOT_FOUND
    fi

    cat "$sql_file"
}

#==============================================================================
# 事务控制
#==============================================================================

# 在事务中执行
pgtool_pg_in_transaction() {
    local sql="$1"
    local wrapped_sql="
BEGIN;
$sql
COMMIT;
"
    pgtool_pg_exec "$wrapped_sql"
}

# 只读执行（添加 SET TRANSACTION READ ONLY）
pgtool_pg_readonly() {
    local sql="$1"
    local wrapped_sql="
SET TRANSACTION READ ONLY;
$sql
"
    pgtool_pg_exec "$wrapped_sql"
}

#==============================================================================
# 辅助查询
#==============================================================================

# 获取所有数据库列表
pgtool_pg_list_databases() {
    pgtool_pg_exec "SELECT datname FROM pg_database WHERE datallowconn ORDER BY datname" --tuples-only --quiet | tr -d ' '
}

# 获取当前数据库
pgtool_pg_current_database() {
    pgtool_pg_query_one "SELECT current_database()"
}

# 获取当前用户
pgtool_pg_current_user() {
    pgtool_pg_query_one "SELECT current_user"
}

# 初始化
pgtool_pg_init
