-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: github_send_schema_export
-- Updated:  2026-09-26T22:01:49.622Z

-- overload
-- language: plpgsql
-- args: p_snapshot_id bigint
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.github_send_schema_export(p_snapshot_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_publish_token uuid;
  v_edge_base_url text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  select s.publish_token
  into v_publish_token
  from archive.schema_export_snapshots s
  where s.id = p_snapshot_id
    and s.published_at is null;

  if v_publish_token is null then
    raise exception 'pending schema export snapshot not found';
  end if;

  select s.edge_base_url
  into v_edge_base_url
  from archive.function_versioning_settings s
  where s.singleton = true;

  if v_edge_base_url is null then
    raise exception 'edge_base_url is not configured';
  end if;

  v_response := extensions.http((
    'POST',
    rtrim(v_edge_base_url, '/') || '/github-send',
    array[extensions.http_header('Content-Type', 'application/json')],
    'application/json',
    jsonb_build_object(
      'schema_export_id', p_snapshot_id,
      'publish_token', v_publish_token
    )::text
  )::extensions.http_request);

  if v_response.status < 200 or v_response.status >= 300 then
    raise exception 'github-send HTTP %: %',
      v_response.status,
      left(coalesce(v_response.content, ''), 1000);
  end if;

  v_body := v_response.content::jsonb;
  if coalesce((v_body->>'ok')::boolean, false) is not true then
    raise exception 'github-send schema export failed: %',
      coalesce(v_body->>'error', v_response.content);
  end if;

  update archive.schema_export_snapshots
  set published_at = now()
  where id = p_snapshot_id;

  return v_body;
end;
$function$
