drop function if exists public.set_my_class_attending(uuid, boolean);

alter function public.get_my_event_attendance() security invoker;
alter function public.set_my_event_attending(uuid, boolean) security invoker;

grant insert, delete, update on public.event_attendance to authenticated;

drop policy if exists event_attendance_insert_self on public.event_attendance;
create policy event_attendance_insert_self
on public.event_attendance
for insert
to authenticated
with check (dancer_id = private.current_dancer_id());

drop policy if exists event_attendance_update_self on public.event_attendance;
create policy event_attendance_update_self
on public.event_attendance
for update
to authenticated
using (dancer_id = private.current_dancer_id())
with check (dancer_id = private.current_dancer_id());

drop policy if exists event_attendance_delete_self on public.event_attendance;
create policy event_attendance_delete_self
on public.event_attendance
for delete
to authenticated
using (dancer_id = private.current_dancer_id());
