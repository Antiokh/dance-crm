-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: github_push_queue_summary
-- Updated:  2026-09-26T20:50:03.863Z

-- overload
-- language: sql
-- args: 
-- returns: TABLE(status text, item_count bigint, min_created_at timestamp with time zone, max_created_at timestamp with time zone, max_try_count integer)

CREATE OR REPLACE FUNCTION archive.github_push_queue_summary()
 RETURNS TABLE(status text, item_count bigint, min_created_at timestamp with time zone, max_created_at timestamp with time zone, max_try_count integer)
 LANGUAGE sql
 STABLE
AS $function$
  select
    q.status,
    count(*),
    min(q.created_at),
    max(q.created_at),
    max(q.try_count)
  from archive.github_push_queue q
  group by q.status
  order by q.status;
$function$
