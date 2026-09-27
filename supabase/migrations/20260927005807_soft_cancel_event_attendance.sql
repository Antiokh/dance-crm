alter table public.event_attendance
  add column if not exists cancelled_at timestamptz;

create index if not exists event_attendance_active_idx
  on public.event_attendance (event_id, dancer_id)
  where cancelled_at is null;

create or replace function public.get_my_event_attendance()
returns table(event_id uuid)
language sql
stable
security invoker
set search_path = ''
as $function$
  select ea.event_id
  from public.event_attendance ea
  where ea.dancer_id = private.current_dancer_id()
    and ea.cancelled_at is null
  order by ea.event_id
$function$;

create or replace function public.set_my_event_attending(
  p_event_id uuid,
  p_attending boolean
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode='P0002';
  end if;

  if p_attending is null then
    raise exception 'attending flag is required' using errcode='22023';
  end if;

  if p_attending then
    if not exists (
      select 1
      from public.dance_events e
      where e.id = p_event_id
        and e.published
        and e.cancelled_at is null
        and coalesce(e.ends_at, e.starts_at) > now()
    ) then
      raise exception 'event is not available for RSVP'
        using errcode='23514';
    end if;

    insert into public.event_attendance (
      event_id,
      dancer_id,
      cancelled_at
    )
    values (
      p_event_id,
      v_dancer_id,
      null
    )
    on conflict (event_id, dancer_id)
    do update
      set cancelled_at = null,
          updated_at = now();

    return true;
  end if;

  update public.event_attendance
  set cancelled_at = now(),
      updated_at = now()
  where event_id = p_event_id
    and dancer_id = v_dancer_id
    and cancelled_at is null;

  return false;
end;
$function$;

revoke delete on public.event_attendance from authenticated;

drop policy if exists event_attendance_delete_self on public.event_attendance;
