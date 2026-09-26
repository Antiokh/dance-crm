-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: push_cron
-- Updated:  2026-09-26T20:33:26.382Z

-- overload
-- language: plpgsql
-- args: 
-- returns: void

CREATE OR REPLACE FUNCTION archive.push_cron()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
begin
    perform archive.push();
end;
$function$
