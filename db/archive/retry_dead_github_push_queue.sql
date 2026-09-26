-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: retry_dead_github_push_queue
-- Updated:  2026-09-26T20:33:19.724Z

-- overload
-- language: plpgsql
-- args: p_requeue_limit integer DEFAULT 100, p_process_limit integer DEFAULT 20
-- returns: integer

CREATE OR REPLACE FUNCTION archive.retry_dead_github_push_queue(p_requeue_limit integer DEFAULT 100, p_process_limit integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
    v_requeued integer;
begin
    v_requeued := archive.requeue_dead_github_push_queue(p_requeue_limit);

    if v_requeued > 0 then
        perform archive.process_github_push_queue(p_process_limit);
    end if;

    return v_requeued;
end;
$function$
