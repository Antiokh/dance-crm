-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_table_publish_payload
-- Updated:  2026-09-26T21:44:00.910Z

-- overload
-- language: plpgsql
-- args: p_table_history_id bigint, p_publish_token uuid
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.get_table_publish_payload(p_table_history_id bigint, p_publish_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_schema_name text;
  v_payload jsonb;
begin
  if not exists (
    select 1
    from archive.github_push_queue q
    where q.item_type='table_bundle'
      and q.table_history_id=p_table_history_id
      and q.publish_token=p_publish_token
      and q.status='pending'
      and q.try_count < 10
  ) then
    raise exception 'invalid or inactive table publish token'
      using errcode='42501';
  end if;

  select q.schema_name
  into v_schema_name
  from archive.github_push_queue q
  where q.item_type='table_bundle'
    and q.table_history_id=p_table_history_id;

  if v_schema_name is null then
    raise exception 'table bundle queue row not found'
      using errcode='P0002';
  end if;

  select jsonb_build_object(
    'schema', v_schema_name,
    'tables', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'table_name', th.table_name,
          'ddl', archive.redact_function_source(th.ddl)
        )
        order by th.table_name
      ),
      '[]'::jsonb
    )
  )
  into v_payload
  from archive.table_history th
  where th.schema_name=v_schema_name
    and th.active=true
    and th.dropped=false;

  return v_payload;
end;
$function$
