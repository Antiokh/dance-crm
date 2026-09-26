-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: github_send_function
-- Updated:  2026-09-26T22:01:26.164Z

-- overload
-- language: plpgsql
-- args: p_function_history_id bigint
-- returns: void

CREATE OR REPLACE FUNCTION archive.github_send_function(p_function_history_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
declare
  v_publish_token uuid;
  v_edge_base_url text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  select q.publish_token
  into v_publish_token
  from archive.github_push_queue q
  where q.function_history_id = p_function_history_id
    and q.status = 'pending';

  if v_publish_token is null then
    raise exception 'pending queue item not found';
  end if;

  select edge_base_url
  into v_edge_base_url
  from archive.function_versioning_settings
  where singleton = true;

  if v_edge_base_url is null then
    raise exception 'function versioning edge_base_url is not configured';
  end if;

  v_response := extensions.http((
    'POST',
    rtrim(v_edge_base_url, '/') || '/github-send',
    array[
      extensions.http_header('Content-Type', 'application/json')
    ],
    'application/json',
    jsonb_build_object(
      'function_history_id', p_function_history_id,
      'publish_token', v_publish_token
    )::text
  )::extensions.http_request);

  if v_response.status < 200 or v_response.status >= 300 then
    raise exception
      'github-send HTTP %: %',
      v_response.status,
      left(coalesce(v_response.content, ''), 1000);
  end if;

  v_body := v_response.content::jsonb;

  if coalesce((v_body->>'ok')::boolean, false) is not true then
    raise exception
      'github-send failed: %',
      coalesce(v_body->>'error', v_response.content);
  end if;
end;
$function$
