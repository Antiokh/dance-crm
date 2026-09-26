-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: calculate_function_version
-- Updated:  2026-09-26T22:01:41.601Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION archive.calculate_function_version()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  select coalesce(max(fh.version), 0) + 1
  into new.version
  from archive.function_history fh
  where fh.schema_name = new.schema_name
    and fh.function_name = new.function_name
    and fh.return_type = new.return_type
    and fh.args = new.args;

  return new;
end;
$function$
