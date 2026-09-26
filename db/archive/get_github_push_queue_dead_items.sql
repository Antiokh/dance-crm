-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: get_github_push_queue_dead_items
-- Updated:  2026-09-26T20:33:21.022Z

-- overload
-- language: sql
-- args: p_limit integer DEFAULT 50
-- returns: TABLE(queue_id bigint, function_history_id bigint, schema_name text, function_name text, args text, return_type text, try_count integer, last_error text, created_at timestamp with time zone)

CREATE OR REPLACE FUNCTION archive.get_github_push_queue_dead_items(p_limit integer DEFAULT 50)
 RETURNS TABLE(queue_id bigint, function_history_id bigint, schema_name text, function_name text, args text, return_type text, try_count integer, last_error text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    select
        q.id,
        q.function_history_id,
        fh.schema_name,
        fh.function_name,
        fh.args,
        fh.return_type,
        q.try_count,
        q.last_error,
        q.created_at
    from archive.github_push_queue q
    join archive.function_history fh
      on fh.id = q.function_history_id
    where q.status = 'dead'
    order by q.id desc
    limit p_limit;
$function$
