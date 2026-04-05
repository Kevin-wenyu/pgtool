SELECT name, setting, COALESCE(unit, '') as unit, context, vartype, boot_val as default, source, category, short_desc, extra_desc
FROM pg_settings
WHERE name = :name;
