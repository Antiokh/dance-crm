-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: refresh_and_publish_schema_export
-- Updated:  2026-09-26T22:01:51.390Z

-- overload
-- language: plpgsql
-- args: 
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.refresh_and_publish_schema_export()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_snapshot_id bigint;
begin
  v_snapshot_id := public.refresh_schema_export();
  return public.github_send_schema_export(v_snapshot_id);
end;
$function$
