drop policy if exists debug_events_service_only on public.debug_events;
create policy debug_events_service_only
on public.debug_events
for all
to service_role
using (true)
with check (true);

drop policy if exists event_closed_legacy on public.event;
create policy event_closed_legacy
on public.event
for all
to anon, authenticated
using (false)
with check (false);

drop policy if exists visit_closed_legacy on public.visit;
create policy visit_closed_legacy
on public.visit
for all
to anon, authenticated
using (false)
with check (false);

create or replace function archive.calculate_function_version()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  select coalesce(max(fh.version), 0) + 1
  into new.version
  from archive.function_history fh
  where fh.schema_name = new.schema_name
    and fh.function_name = new.function_name
    and fh.return_type = new.return_type
    and fh.args = new.args;

  return new;
end;
$function$;

drop trigger if exists before_insert_function_history on archive.function_history;
create trigger before_insert_function_history
before insert on archive.function_history
for each row
execute function archive.calculate_function_version();

alter extension "mansueli@function_vc" drop sequence archive.function_history_id_seq;
alter extension "mansueli@function_vc" drop table archive.function_history;
alter extension "mansueli@function_vc" drop function archive.save_function_history(text,text,text,text,text,text);
alter extension "mansueli@function_vc" drop function archive.setup_function_history(text);
alter extension "mansueli@function_vc" drop schema archive;
drop extension "mansueli@function_vc";

drop extension if exists "supabase@dbdev";
drop extension if exists "olirice@index_advisor";
