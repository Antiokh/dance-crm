-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: process_github_push_queue
-- Updated:  2026-09-26T22:01:27.463Z

-- overload
-- language: plpgsql
-- args: p_limit integer DEFAULT 5
-- returns: integer

CREATE OR REPLACE FUNCTION archive.process_github_push_queue(p_limit integer DEFAULT 5)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select id,item_type,function_history_id,table_history_id,try_count
    from archive.github_push_queue
    where status='pending'
      and try_count < 10
    order by id
    limit greatest(p_limit,0)
    for update skip locked
  loop
    begin
      if r.item_type='function' then
        perform archive.github_send_function(r.function_history_id);
      elsif r.item_type='table_bundle' then
        perform archive.github_send_tables(r.table_history_id);
      else
        raise exception 'unsupported queue item type: %', r.item_type;
      end if;

      update archive.github_push_queue
      set status='done',
          pushed_at=now(),
          last_error=null
      where id=r.id;

      v_count := v_count+1;
    exception when others then
      update archive.github_push_queue
      set try_count=try_count+1,
          last_error=SQLERRM,
          status=case when try_count+1 >= 10 then 'dead' else 'pending' end
      where id=r.id;
    end;
  end loop;

  return v_count;
end;
$function$
