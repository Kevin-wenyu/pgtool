#!/bin/bash
# lib/config.sh - PostgreSQL configuration utilities
# Provides system resource detection, configuration retrieval, recommendation calculations,
# parameter analysis, and export functionality

# 必须先加载 core.sh 和 pg.sh
if [[ -z "${PGTOOL_VERSION:-}" ]]; then
    echo "错误: 必须先加载 core.sh" >&2
    exit 1
fi

#==============================================================================
# 系统资源检测
#==============================================================================

# 获取系统内存大小（KB）
# 从 /proc/meminfo (Linux) 或 sysctl (macOS) 读取
pgtool_config_detect_memory() {
    local mem_kb=0

    if [[ -f /proc/meminfo ]]; then
        # Linux: 从 /proc/meminfo 读取 MemTotal
        mem_kb=$(grep -E '^MemTotal:' /proc/meminfo | awk '{print $2}')
    elif command -v sysctl &>/dev/null; then
        # macOS/BSD: 使用 sysctl hw.memsize (返回字节，转换为 KB)
        local mem_bytes
        mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        mem_kb=$((mem_bytes / 1024))
    fi

    echo "${mem_kb:-0}"
}

# 获取 CPU 核心数
pgtool_config_detect_cpus() {
    local cpus=1

    if command -v nproc &>/dev/null; then
        # Linux: 使用 nproc
        cpus=$(nproc 2>/dev/null || echo 1)
    elif [[ -f /proc/cpuinfo ]]; then
        # 备用: 从 /proc/cpuinfo 计数
        cpus=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
    elif command -v sysctl &>/dev/null; then
        # macOS/BSD: 使用 sysctl
        cpus=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    fi

    echo "${cpus:-1}"
}

# 检测磁盘类型 (SSD 或 HDD)
# 通过检查 /sys/block/{device}/queue/rotational 或使用 diskutil (macOS)
pgtool_config_detect_disk_type() {
    local disk_type="unknown"

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux: 检查 rotational 标志
        # 0 = SSD, 1 = HDD
        local rotational
        if [[ -d /sys/block ]]; then
            # 尝试找到根目录所在的磁盘设备
            local root_dev
            root_dev=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/^\(sd[a-z]\|nvme[0-9]n[0-9]\|xvd[a-z]\|hd[a-z]\|vd[a-z]\).*/\1/')
            if [[ -n "$root_dev" ]] && [[ -f "/sys/block/${root_dev}/queue/rotational" ]]; then
                rotational=$(cat "/sys/block/${root_dev}/queue/rotational" 2>/dev/null)
                if [[ "$rotational" == "0" ]]; then
                    disk_type="SSD"
                elif [[ "$rotational" == "1" ]]; then
                    disk_type="HDD"
                fi
            else
                # 尝试检测第一个块设备
                for dev in /sys/block/sd* /sys/block/nvme* /sys/block/xvd* /sys/block/vd*; do
                    if [[ -f "$dev/queue/rotational" ]]; then
                        rotational=$(cat "$dev/queue/rotational" 2>/dev/null)
                        if [[ "$rotational" == "0" ]]; then
                            disk_type="SSD"
                            break
                        elif [[ "$rotational" == "1" ]]; then
                            disk_type="HDD"
                            break
                        fi
                    fi
                done
            fi
        fi

        # 如果检测到 NVMe，一定是 SSD
        if [[ -e /sys/block/nvme* ]]; then
            disk_type="SSD"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: 使用 diskutil
        local disk_id
        disk_id=$(diskutil info / 2>/dev/null | grep 'Device Identifier' | awk '{print $NF}')
        if [[ -n "$disk_id" ]]; then
            local solid_state
            solid_state=$(diskutil info "$disk_id" 2>/dev/null | grep 'Solid State' | awk '{print $NF}')
            if [[ "$solid_state" == "Yes" ]]; then
                disk_type="SSD"
            elif [[ "$solid_state" == "No" ]]; then
                disk_type="HDD"
            fi
        fi
    fi

    echo "$disk_type"
}

#==============================================================================
# 配置参数检索
#==============================================================================

# 获取所有 PostgreSQL 配置参数
# 返回格式: name|setting|unit|category|short_desc|context|vartype
pgtool_config_get_all() {
    local sql="SELECT name, setting, unit, category, short_desc, context, vartype FROM pg_settings ORDER BY category, name"
    pgtool_pg_exec "$sql" --tuples-only
}

# 获取特定配置参数值
# 参数: name - 参数名称
pgtool_config_get_param() {
    local name="$1"
    local sql="SELECT setting FROM pg_settings WHERE name = '${name}'"
    pgtool_pg_query_one "$sql"
}

# 获取与默认值不同的参数
# 返回格式: name|setting|boot_val|unit|category
pgtool_config_get_changed() {
    local sql="SELECT name, setting, boot_val, unit, category FROM pg_settings WHERE setting != boot_val ORDER BY category, name"
    pgtool_pg_exec "$sql" --tuples-only
}

# 按类别获取配置参数
# 参数: category - 类别名称 (如 'Memory', 'Query Tuning')
pgtool_config_get_by_category() {
    local category="$1"
    local sql="SELECT name, setting, unit, short_desc FROM pg_settings WHERE category ILIKE '%${category}%' ORDER BY name"
    pgtool_pg_exec "$sql" --tuples-only
}

# 获取 PostgreSQL 版本号 (数值形式, 如 150002 表示 15.2)
pgtool_config_pg_version() {
    local sql="SELECT current_setting('server_version_num')::int"
    pgtool_pg_query_one "$sql"
}

# 获取 max_connections 设置值
pgtool_config_get_max_connections() {
    local sql="SELECT setting::int FROM pg_settings WHERE name = 'max_connections'"
    pgtool_pg_query_one "$sql"
}

#==============================================================================
# 推荐值计算
#==============================================================================

# 计算 shared_buffers 推荐值
# 规则: 25% RAM, 最大 8GB (8192 MB)
# 参数: ram_kb - 系统内存大小 (KB)
pgtool_config_calc_shared_buffers() {
    local ram_kb="$1"
    local ram_mb=$((ram_kb / 1024))
    local shared_mb=$((ram_mb / 4))
    local max_mb=8192

    if [[ $shared_mb -gt $max_mb ]]; then
        shared_mb=$max_mb
    fi

    echo "${shared_mb}MB"
}

# 计算 effective_cache_size 推荐值
# 规则: 50% RAM
# 参数: ram_kb - 系统内存大小 (KB)
pgtool_config_calc_effective_cache_size() {
    local ram_kb="$1"
    local ram_mb=$((ram_kb / 1024))
    local cache_mb=$((ram_mb / 2))

    echo "${cache_mb}MB"
}

# 计算 work_mem 推荐值
# 规则: RAM / max_connections / 4 (为复杂查询预留空间)
# 参数: ram_kb - 系统内存大小 (KB)
# 参数: max_conn - 最大连接数
pgtool_config_calc_work_mem() {
    local ram_kb="$1"
    local max_conn="${2:-100}"

    if [[ $max_conn -lt 1 ]]; then
        max_conn=1
    fi

    local work_kb=$((ram_kb / max_conn / 4))
    local work_mb=$((work_kb / 1024))

    # 最小 4MB，最大 256MB
    if [[ $work_mb -lt 4 ]]; then
        work_mb=4
    elif [[ $work_mb -gt 256 ]]; then
        work_mb=256
    fi

    echo "${work_mb}MB"
}

# 计算 maintenance_work_mem 推荐值
# 规则: 1GB 或 RAM 的 10% (取较小值)
# 参数: ram_kb - 系统内存大小 (KB)
pgtool_config_calc_maintenance_work_mem() {
    local ram_kb="$1"
    local ram_mb=$((ram_kb / 1024))
    local maint_mb=$((ram_mb / 10))
    local max_maint_mb=1024

    if [[ $maint_mb -gt $max_maint_mb ]]; then
        maint_mb=$max_maint_mb
    fi

    # 最小 64MB
    if [[ $maint_mb -lt 64 ]]; then
        maint_mb=64
    fi

    echo "${maint_mb}MB"
}

#==============================================================================
# 配置参数分析
#==============================================================================

# 分析单个配置参数
# 参数: name - 参数名称
# 参数: current - 当前值
# 参数: total_ram - 总内存 (KB)
# 参数: max_conn - 最大连接数
pgtool_config_analyze_param() {
    local name="$1"
    local current="$2"
    local total_ram="$3"
    local max_conn="$4"

    local status="ok"
    local recommendation=""
    local reason=""

    case "$name" in
        shared_buffers)
            local current_mb
            current_mb=$(echo "$current" | sed 's/[^0-9]//g')
            if [[ -z "$current_mb" ]]; then
                current_mb=$(($(pgtool_config_get_param "shared_buffers") / 1024))
            fi
            local recommended
            recommended=$(pgtool_config_calc_shared_buffers "$total_ram" | sed 's/[^0-9]//g')

            if [[ $current_mb -lt $((recommended / 2)) ]]; then
                status="warning"
                recommendation="建议设置为 ${recommended}MB"
                reason="shared_buffers 过低，可能影响缓存命中率"
            elif [[ $current_mb -gt $((recommended * 2)) ]]; then
                status="warning"
                recommendation="建议设置为 ${recommended}MB"
                reason="shared_buffers 过高，可能浪费内存"
            fi
            ;;

        effective_cache_size)
            local current_mb
            current_mb=$(echo "$current" | sed 's/[^0-9]//g')
            if [[ -z "$current_mb" ]]; then
                current_mb=$((total_ram / 1024 / 2))  # 估计值
            fi
            local recommended
            recommended=$(pgtool_config_calc_effective_cache_size "$total_ram" | sed 's/[^0-9]//g')

            if [[ $current_mb -lt $((recommended / 4)) ]]; then
                status="warning"
                recommendation="建议设置为 ${recommended}MB"
                reason="effective_cache_size 过低，查询规划器可能做出次优选择"
            fi
            ;;

        work_mem)
            local current_mb
            current_mb=$(echo "$current" | sed 's/[^0-9]//g')
            if [[ -z "$current_mb" ]]; then
                current_mb=4
            fi
            local recommended
            recommended=$(pgtool_config_calc_work_mem "$total_ram" "$max_conn" | sed 's/[^0-9]//g')

            if [[ $current_mb -lt 4 ]]; then
                status="warning"
                recommendation="建议至少 4MB"
                reason="work_mem 过低，复杂查询可能使用磁盘排序"
            elif [[ $current_mb -gt 256 ]]; then
                status="warning"
                recommendation="建议不超过 256MB (考虑使用 maintenance_work_mem)"
                reason="work_mem 过高，大量连接时可能耗尽内存"
            fi
            ;;

        maintenance_work_mem)
            local current_mb
            current_mb=$(echo "$current" | sed 's/[^0-9]//g')
            if [[ -z "$current_mb" ]]; then
                current_mb=64
            fi
            local recommended
            recommended=$(pgtool_config_calc_maintenance_work_mem "$total_ram" | sed 's/[^0-9]//g')

            if [[ $current_mb -lt 64 ]]; then
                status="warning"
                recommendation="建议至少 64MB"
                reason="maintenance_work_mem 过低，VACUUM 和 CREATE INDEX 可能很慢"
            fi
            ;;

        max_connections)
            if [[ $current -gt 500 ]]; then
                status="warning"
                recommendation="考虑使用连接池 (pgbouncer)"
                reason="max_connections 过高，可能导致内存压力和性能下降"
            elif [[ $current -lt 10 ]]; then
                status="warning"
                recommendation="考虑增加连接数限制"
                reason="max_connections 过低，可能限制应用并发"
            fi
            ;;

        random_page_cost)
            local disk_type
            disk_type=$(pgtool_config_detect_disk_type)
            if [[ "$disk_type" == "SSD" ]] && [[ $(echo "$current > 1.1" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                status="warning"
                recommendation="SSD 建议设置为 1.1"
                reason="SSD 随机读取性能接近顺序读取，应降低 random_page_cost"
            elif [[ "$disk_type" == "HDD" ]] && [[ $(echo "$current < 3" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                status="warning"
                recommendation="HDD 建议保持 4.0"
                reason="HDD 随机读取较慢，过低的 random_page_cost 可能导致全表扫描"
            fi
            ;;

        checkpoint_completion_target)
            if [[ $(echo "$current < 0.5" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                status="warning"
                recommendation="建议设置为 0.9"
                reason="checkpoint_completion_target 过低可能导致 I/O 尖峰"
            fi
            ;;

        wal_buffers)
            if [[ -z "$current" ]] || [[ "$current" == "-1" ]]; then
                status="ok"
                reason="使用自动设置 (shared_buffers 的 1/32)"
            fi
            ;;

        *)
            status="unknown"
            reason="没有该参数的分析规则"
            ;;
    esac

    echo "${status}|${recommendation}|${reason}"
}

#==============================================================================
# 配置导出
#==============================================================================

# 导出配置为 postgresql.conf 格式
# 参数: category_filter (可选) - 只导出特定类别的参数
pgtool_config_export_conf() {
    local category_filter="${1:-}"

    local sql
    if [[ -n "$category_filter" ]]; then
        sql="SELECT name || ' = ' || setting || COALESCE(unit, '') FROM pg_settings WHERE category ILIKE '%${category_filter}%' ORDER BY name"
    else
        sql="SELECT name || ' = ' || setting || COALESCE(unit, '') FROM pg_settings ORDER BY name"
    fi

    local output
    output=$(pgtool_pg_exec "$sql" --tuples-only --quiet 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        echo "# Generated by pgtool config export"
        echo "# $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        if [[ -n "$category_filter" ]]; then
            echo "# Category: $category_filter"
            echo ""
        fi
        echo "$output"
    else
        return $EXIT_SQL_ERROR
    fi
}

# 导出配置为 ALTER SYSTEM 命令
# 参数: category_filter (可选) - 只导出特定类别的参数
pgtool_config_export_alter_system() {
    local category_filter="${1:-}"

    local sql
    if [[ -n "$category_filter" ]]; then
        sql="SELECT 'ALTER SYSTEM SET ' || name || ' = ' || quote_literal(setting || COALESCE(unit, '')) || ';' FROM pg_settings WHERE category ILIKE '%${category_filter}%' ORDER BY name"
    else
        sql="SELECT 'ALTER SYSTEM SET ' || name || ' = ' || quote_literal(setting || COALESCE(unit, '')) || ';' FROM pg_settings ORDER BY name"
    fi

    local output
    output=$(pgtool_pg_exec "$sql" --tuples-only --quiet 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        echo "-- Generated by pgtool config export-alter-system"
        echo "-- $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        if [[ -n "$category_filter" ]]; then
            echo "-- Category: $category_filter"
            echo ""
        fi
        echo "$output"
    else
        return $EXIT_SQL_ERROR
    fi
}
