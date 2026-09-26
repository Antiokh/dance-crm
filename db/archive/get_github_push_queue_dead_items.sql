-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: get_github_push_queue_dead_items
-- Updated:  2026-09-26T22:01:20.800Z

-- overload
-- language: sql
-- args: p_limit integer DEFAULT 50
-- returns: TABLE(queue_id bigint, item_type text, function_history_id bigint, table_history_id bigint, schema_name text, object_name text, try_count integer, last_error text, created_at timestamp with time zone)

CREATE OR REPLACE FUNCTION archive.get_github_push_queue_dead_items(p_limit integer DEFAULT 50)
 RETURNS TABLE(queue_id bigint, item_type text, function_history_id bigint, table_history_id bigint, schema_name text, object_name text, try_count integer, last_error text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
  select
    q.id,q.item_type,q.function_history_id,q.table_history_id,
    coalesce(fh.schema_name,th.schema_name),
    coalesce(fh.function_name,th.table_name),
    q.try_count,q.last_error,q.created_at
  from archive.github_push_queue q
  left join archive.function_history fh on fh.id=q.function_history_id
  left join archive.table_history th on th.id=q.table_history_id
  where q.status='dead'
  order by q.id desc
  limit p_limit;
$function$
