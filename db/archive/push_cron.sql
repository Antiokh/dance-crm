-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: push_cron
-- Updated:  2026-09-26T22:01:02.889Z

-- overload
-- language: plpgsql
-- args: 
-- returns: void

CREATE OR REPLACE FUNCTION archive.push_cron()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
begin
  perform archive.push();
end;
$function$
