SELECT name, setting, COALESCE(unit, '') as unit, context, vartype, source, boot_val as default, category, short_desc
FROM pg_settings
WHERE (:category = '' OR category ILIKE '%' || :category || '%')
ORDER BY category, name;
