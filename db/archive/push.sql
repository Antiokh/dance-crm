-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: push
-- Updated:  2026-09-26T20:50:12.461Z

-- overload
-- language: plpgsql
-- args: 
-- returns: void

CREATE OR REPLACE FUNCTION archive.push()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
begin
  perform archive.push_updated_functions_to_github('archive');
  perform archive.push_updated_functions_to_github('private');
  perform archive.push_updated_functions_to_github('public');
end;
$function$
