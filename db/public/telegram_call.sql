-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: telegram_call
-- Updated:  2026-09-26T20:34:49.713Z

-- overload
-- language: plpgsql
-- args: method text, payload jsonb
-- returns: json

CREATE OR REPLACE FUNCTION public.telegram_call(method text, payload jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pgmq', 'vault'
AS $function$
declare
  token text := '<REDACTED_LEGACY_TELEGRAM_BOT_TOKEN>';
  url text := 'https://api.telegram.org/bot' || token || '/' || method;
begin
  return (
    select content::json
    from http((
      'POST',
      url,
      ARRAY[
        http_header('Content-Type', 'application/json')
      ],
      'application/json',
      payload::text
    )::http_request)
  );
end;
$function$
