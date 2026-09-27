create table if not exists public.event_attendance (
  event_id uuid not null references public.dance_events(id) on delete cascade,
  dancer_id uuid not null references public.dancer(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, dancer_id)
);

create index if not exists event_attendance_dancer_idx
  on public.event_attendance (dancer_id, event_id);

drop trigger if exists event_attendance_touch_updated_at
  on public.event_attendance;

create trigger event_attendance_touch_updated_at
before update on public.event_attendance
for each row execute function private.touch_updated_at();

alter table public.event_attendance enable row level security;

grant select on public.event_attendance to authenticated;

drop policy if exists event_attendance_select on public.event_attendance;
create policy event_attendance_select
on public.event_attendance
for select
to authenticated
using (
  dancer_id = private.current_dancer_id()
  or private.has_app_role('administrator'::public.app_role)
);

create or replace function public.get_my_event_attendance()
returns table(event_id uuid)
language sql
stable
security definer
set search_path = ''
as $function$
  select ea.event_id
  from public.event_attendance ea
  where ea.dancer_id = private.current_dancer_id()
  order by ea.event_id
$function$;

revoke all on function public.get_my_event_attendance() from public;
revoke all on function public.get_my_event_attendance() from anon;
grant execute on function public.get_my_event_attendance() to authenticated;

create or replace function public.set_my_event_attending(
  p_event_id uuid,
  p_attending boolean
)
returns boolean
language plpgsql
security definer
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
      dancer_id
    )
    values (
      p_event_id,
      v_dancer_id
    )
    on conflict (event_id, dancer_id)
    do update set updated_at = now();

    return true;
  end if;

  delete from public.event_attendance
  where event_id = p_event_id
    and dancer_id = v_dancer_id;

  return false;
end;
$function$;

revoke all on function public.set_my_event_attending(uuid, boolean) from public;
revoke all on function public.set_my_event_attending(uuid, boolean) from anon;
grant execute on function public.set_my_event_attending(uuid, boolean) to authenticated;

create or replace function public.set_my_class_attending(
  p_slot_id uuid,
  p_attending boolean
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_booking public.bookings%rowtype;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode='P0002';
  end if;

  if p_attending is null then
    raise exception 'attending flag is required' using errcode='22023';
  end if;

  select *
  into v_booking
  from public.bookings b
  where b.slot_id = p_slot_id
    and b.dancer_id = v_dancer_id
  for update;

  if p_attending then
    if v_booking.id is not null
      and v_booking.status <> 'cancelled'::public.booking_status
    then
      return jsonb_build_object(
        'attending', true,
        'booking_id', v_booking.id,
        'status', v_booking.status
      );
    end if;

    select *
    into v_booking
    from public.book_class_slot(p_slot_id, null::smallint);

    return jsonb_build_object(
      'attending', true,
      'booking_id', v_booking.id,
      'status', v_booking.status
    );
  end if;

  if v_booking.id is not null
    and v_booking.status <> 'cancelled'::public.booking_status
  then
    select *
    into v_booking
    from public.cancel_my_booking(v_booking.id);
  end if;

  return jsonb_build_object(
    'attending', false,
    'booking_id', case when v_booking.id is null then null else v_booking.id end,
    'status', null
  );
end;
$function$;

revoke all on function public.set_my_class_attending(uuid, boolean) from public;
revoke all on function public.set_my_class_attending(uuid, boolean) from anon;
grant execute on function public.set_my_class_attending(uuid, boolean) to authenticated;
