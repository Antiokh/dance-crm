-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: requeue_dead_github_push_queue
-- Updated:  2026-09-26T20:50:09.565Z

-- overload
-- language: plpgsql
-- args: p_limit integer DEFAULT 100
-- returns: integer

CREATE OR REPLACE FUNCTION archive.requeue_dead_github_push_queue(p_limit integer DEFAULT 100)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_count integer;
begin
  with target_rows as (
    select q.id
    from archive.github_push_queue q
    where q.status = 'dead'
    order by q.id
    limit p_limit
    for update skip locked
  )
  update archive.github_push_queue q
  set status = 'pending',
      try_count = 0,
      last_error = null,
      publish_token = extensions.gen_random_uuid()
  from target_rows t
  where q.id = t.id;

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$
