-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: github_push_queue_summary
-- Updated:  2026-09-26T22:01:19.338Z

-- overload
-- language: sql
-- args: 
-- returns: TABLE(item_type text, status text, item_count bigint, min_created_at timestamp with time zone, max_created_at timestamp with time zone, max_try_count integer)

CREATE OR REPLACE FUNCTION archive.github_push_queue_summary()
 RETURNS TABLE(item_type text, status text, item_count bigint, min_created_at timestamp with time zone, max_created_at timestamp with time zone, max_try_count integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
  select q.item_type,q.status,count(*),min(q.created_at),max(q.created_at),max(q.try_count)
  from archive.github_push_queue q
  group by q.item_type,q.status
  order by q.item_type,q.status;
$function$
