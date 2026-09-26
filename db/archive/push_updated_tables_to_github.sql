-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: push_updated_tables_to_github
-- Updated:  2026-09-26T22:01:37.769Z

-- overload
-- language: plpgsql
-- args: p_schema text DEFAULT 'public'::text, p_immediate_limit integer DEFAULT 0
-- returns: integer

CREATE OR REPLACE FUNCTION archive.push_updated_tables_to_github(p_schema text DEFAULT 'public'::text, p_immediate_limit integer DEFAULT 0)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
declare
  v_count integer;
  v_revision_id bigint;
begin
  select count(*),max(changed.table_history_id)
  into v_count,v_revision_id
  from archive.update_tables(p_schema) changed;

  if coalesce(v_count,0) > 0 then
    insert into archive.github_push_queue(item_type,table_history_id,schema_name)
    values ('table_bundle',v_revision_id,p_schema)
    on conflict (table_history_id)
      where item_type='table_bundle'
      do nothing;
  end if;

  if p_immediate_limit > 0 then
    perform archive.process_github_push_queue(p_immediate_limit);
  end if;

  return coalesce(v_count,0);
end;
$function$
