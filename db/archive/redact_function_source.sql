-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: redact_function_source
-- Updated:  2026-09-26T22:01:04.575Z

-- overload
-- language: sql
-- args: p_source text
-- returns: text

CREATE OR REPLACE FUNCTION archive.redact_function_source(p_source text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
  select regexp_replace(
    regexp_replace(
      regexp_replace(
        coalesce(p_source, ''),
        '[0-9]{7,12}:[A-Za-z0-9_-]{25,}',
        '<REDACTED_LEGACY_TELEGRAM_BOT_TOKEN>',
        'g'
      ),
      'sb_secret_[A-Za-z0-9_-]{10,}',
      '<REDACTED_SUPABASE_SECRET_KEY>',
      'g'
    ),
    'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}',
    '<REDACTED_JWT>',
    'g'
  );
$function$
