SELECT
    name,
    setting,
    COALESCE(unit, '') AS unit,
    context,
    vartype,
    boot_val AS default_value,
    source,
    category,
    short_desc,
    extra_desc
FROM pg_settings
WHERE 1=1
ORDER BY category, name;
