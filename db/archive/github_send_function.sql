-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: github_send_function
-- Updated:  2026-09-26T20:33:15.402Z

-- overload
-- language: plpgsql
-- args: p_function_history_id bigint
-- returns: void

CREATE OR REPLACE FUNCTION archive.github_send_function(p_function_history_id bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  v_publish_token uuid;
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

  v_response := extensions.http((
    'POST',
    'https://acmgtkethcijxgldrfgw.supabase.co/functions/v1/github-send',
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
    raise exception 'github-send HTTP %: %', v_response.status, left(coalesce(v_response.content,''), 1000);
  end if;

  v_body := v_response.content::jsonb;

  if coalesce((v_body->>'ok')::boolean, false) is not true then
    raise exception 'github-send failed: %', coalesce(v_body->>'error', v_response.content);
  end if;
end;
$function$
