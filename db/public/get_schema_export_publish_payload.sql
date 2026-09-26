-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_schema_export_publish_payload
-- Updated:  2026-09-26T22:01:48.250Z

-- overload
-- language: plpgsql
-- args: p_snapshot_id bigint, p_publish_token uuid
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.get_schema_export_publish_payload(p_snapshot_id bigint, p_publish_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_snapshot jsonb;
begin
  select s.snapshot
  into v_snapshot
  from archive.schema_export_snapshots s
  where s.id = p_snapshot_id
    and s.publish_token = p_publish_token
    and s.published_at is null;

  if v_snapshot is null then
    raise exception 'invalid or inactive schema export publish token'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'path', 'db/ddl.json',
    'content', jsonb_pretty(v_snapshot),
    'message', '[CF-Pages-Skip] schema export refresh: db/ddl.json'
  );
end;
$function$
