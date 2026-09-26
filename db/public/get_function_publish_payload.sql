-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_function_publish_payload
-- Updated:  2026-09-26T20:50:25.004Z

-- overload
-- language: plpgsql
-- args: p_function_history_id bigint, p_publish_token uuid
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.get_function_publish_payload(p_function_history_id bigint, p_publish_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_schema text;
  v_function_name text;
  v_payload jsonb;
begin
  if not exists (
    select 1
    from archive.github_push_queue q
    where q.function_history_id = p_function_history_id
      and q.publish_token = p_publish_token
      and q.status = 'pending'
      and q.try_count < 10
  ) then
    raise exception 'invalid or inactive publish token'
      using errcode = '42501';
  end if;

  select fh.schema_name, fh.function_name
  into v_schema, v_function_name
  from archive.function_history fh
  where fh.id = p_function_history_id;

  if v_schema is null or v_function_name is null then
    raise exception 'function history row not found'
      using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'schema', v_schema,
    'function_name', v_function_name,
    'overloads', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'language', fh.lang_settings,
          'args', fh.args,
          'return_type', fh.return_type,
          'source_code', archive.redact_function_source(fh.source_code)
        )
        order by fh.lang_settings, fh.args, fh.return_type
      ),
      '[]'::jsonb
    )
  )
  into v_payload
  from archive.function_history fh
  where fh.schema_name = v_schema
    and fh.function_name = v_function_name
    and fh.active = true;

  return v_payload;
end;
$function$
