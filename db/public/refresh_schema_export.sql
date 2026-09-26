-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: refresh_schema_export
-- Updated:  2026-09-26T22:01:46.882Z

-- overload
-- language: plpgsql
-- args: 
-- returns: bigint

CREATE OR REPLACE FUNCTION public.refresh_schema_export()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id bigint;
begin
  insert into archive.schema_export_snapshots(snapshot)
  values (public.get_complete_schema())
  returning id into v_id;

  return v_id;
end;
$function$
