-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: push
-- Updated:  2026-09-26T21:43:06.053Z

-- overload
-- language: plpgsql
-- args: 
-- returns: void

CREATE OR REPLACE FUNCTION archive.push()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
begin
  perform archive.push_updated_functions_to_github('archive',0);
  perform archive.push_updated_functions_to_github('private',0);
  perform archive.push_updated_functions_to_github('public',0);

  perform archive.push_updated_tables_to_github('archive',0);
  perform archive.push_updated_tables_to_github('private',0);
  perform archive.push_updated_tables_to_github('public',0);
end;
$function$
