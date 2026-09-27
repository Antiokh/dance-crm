do $$
begin
  create type public.overbook_request_status as enum (
    'pending',
    'approved',
    'rejected',
    'cancelled',
    'resolved'
  );
exception
  when duplicate_object then null;
end
$$;

create table if not exists public.overbook_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete cascade,
  slot_id uuid not null references public.class_slots(id) on delete cascade,
  dancer_id uuid not null references public.dancer(id) on delete cascade,
  status public.overbook_request_status not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.dancer(id) on delete set null,
  review_note text,
  notification_queued_at timestamptz,
  notification_sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint overbook_review_shape check (
    (
      status = 'pending'::public.overbook_request_status
      and reviewed_at is null
      and reviewed_by is null
    )
    or status <> 'pending'::public.overbook_request_status
  )
);

create index if not exists overbook_requests_slot_status_idx
  on public.overbook_requests (slot_id, status, requested_at);

create index if not exists overbook_requests_dancer_idx
  on public.overbook_requests (dancer_id, requested_at desc);

drop trigger if exists overbook_requests_touch_updated_at
  on public.overbook_requests;

create trigger overbook_requests_touch_updated_at
before update on public.overbook_requests
for each row execute function private.touch_updated_at();

alter table public.overbook_requests enable row level security;

grant select on public.overbook_requests to authenticated;

drop policy if exists overbook_requests_select on public.overbook_requests;
create policy overbook_requests_select
on public.overbook_requests
for select
to authenticated
using (
  dancer_id = private.current_dancer_id()
  or private.can_operate_slot(slot_id)
);

create or replace function private.sync_overbook_request_for_booking(
  p_booking_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_booking public.bookings%rowtype;
  v_request_id uuid;
begin
  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    return null;
  end if;

  if v_booking.status = 'waitlisted'::public.booking_status then
    insert into public.overbook_requests (
      booking_id,
      slot_id,
      dancer_id,
      status,
      requested_at,
      reviewed_at,
      reviewed_by,
      review_note
    )
    values (
      v_booking.id,
      v_booking.slot_id,
      v_booking.dancer_id,
      'pending'::public.overbook_request_status,
      now(),
      null,
      null,
      null
    )
    on conflict (booking_id)
    do update
      set slot_id = excluded.slot_id,
          dancer_id = excluded.dancer_id,
          status = 'pending'::public.overbook_request_status,
          requested_at = now(),
          reviewed_at = null,
          reviewed_by = null,
          review_note = null
    returning id into v_request_id;

    return v_request_id;
  end if;

  update public.overbook_requests
  set status = case
        when v_booking.status = 'cancelled'::public.booking_status
          then 'cancelled'::public.overbook_request_status
        else 'resolved'::public.overbook_request_status
      end,
      reviewed_at = coalesce(reviewed_at, now())
  where booking_id = v_booking.id
    and status = 'pending'::public.overbook_request_status
  returning id into v_request_id;

  return v_request_id;
end;
$function$;

revoke all on function private.sync_overbook_request_for_booking(uuid) from public;
revoke all on function private.sync_overbook_request_for_booking(uuid) from anon;
revoke all on function private.sync_overbook_request_for_booking(uuid) from authenticated;

create or replace function private.book_class_slot_for_current(
  p_slot_id uuid,
  p_dance_role_id smallint default null::smallint
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_slot record;
  v_partner boolean;
  v_role smallint := p_dance_role_id;
  v_capacity integer;
  v_booked_count integer;
  v_status public.booking_status;
  v_booking public.bookings%rowtype;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found'
      using errcode='P0002';
  end if;

  select cs.*, g.style_id
  into v_slot
  from public.class_slots cs
  join public.dance_group g on g.id = cs.group_id
  where cs.id = p_slot_id
  for update of cs;

  if not found then
    raise exception 'class slot not found'
      using errcode='P0002';
  end if;

  if not private.can_view_class(v_slot.group_id, v_slot.visibility) then
    raise exception 'class slot access denied'
      using errcode='42501';
  end if;

  if v_slot.status <> 'scheduled'::public.class_slot_status then
    raise exception 'class slot is not bookable'
      using errcode='23514';
  end if;

  if v_slot.starts_at <= now() then
    raise exception 'class slot has already started'
      using errcode='23514';
  end if;

  select *
  into v_booking
  from public.bookings b
  where b.slot_id = p_slot_id
    and b.dancer_id = v_dancer_id
  for update;

  if found and v_booking.status <> 'cancelled'::public.booking_status then
    raise exception 'booking already exists for this class'
      using errcode='23505';
  end if;

  select s.is_partner_dance
  into v_partner
  from public.l_dance_style s
  where s.id = v_slot.style_id;

  if coalesce(v_partner, true) then
    if v_role is null then
      v_role := private.default_dance_role_for_style(
        v_dancer_id,
        v_slot.style_id
      );
    end if;

    if v_role is null or not exists (
      select 1
      from public.l_dance_role r
      where r.id = v_role
    ) then
      raise exception 'dance role is required for partner dance'
        using errcode='23514';
    end if;
  else
    v_role := null;
  end if;

  v_capacity := private.effective_slot_capacity(p_slot_id);

  select count(*)::integer
  into v_booked_count
  from public.bookings
  where slot_id = p_slot_id
    and status = 'booked'::public.booking_status;

  if v_capacity is not null and v_booked_count >= v_capacity then
    v_status := 'waitlisted'::public.booking_status;
  else
    v_status := 'booked'::public.booking_status;
  end if;

  if v_booking.id is not null then
    update public.bookings
    set status = v_status,
        attendance_status = null,
        dance_role_id = v_role,
        is_trial = false,
        booked_at = now(),
        cancelled_at = null,
        cancellation_type = null
    where id = v_booking.id
    returning * into v_booking;
  else
    insert into public.bookings (
      slot_id,
      dancer_id,
      status,
      dance_role_id,
      is_trial
    )
    values (
      p_slot_id,
      v_dancer_id,
      v_status,
      v_role,
      false
    )
    returning * into v_booking;
  end if;

  perform private.sync_overbook_request_for_booking(v_booking.id);

  return v_booking;
end;
$function$;

create or replace function private.cancel_my_booking_internal(
  p_booking_id uuid
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_booking public.bookings%rowtype;
  v_slot_start timestamptz;
  v_was_booked boolean;
begin
  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
    and dancer_id = v_dancer_id
  for update;

  if not found then
    raise exception 'booking not found'
      using errcode='P0002';
  end if;

  select cs.starts_at
  into v_slot_start
  from public.class_slots cs
  where cs.id = v_booking.slot_id;

  if v_booking.status = 'cancelled'::public.booking_status then
    raise exception 'booking is already cancelled'
      using errcode='23514';
  end if;

  if v_slot_start <= now() then
    raise exception 'class slot has already started'
      using errcode='23514';
  end if;

  v_was_booked := v_booking.status = 'booked'::public.booking_status;

  update public.bookings
  set status = 'cancelled'::public.booking_status,
      cancelled_at = now(),
      cancellation_type = 'user'::public.booking_cancellation_type
  where id = p_booking_id
  returning * into v_booking;

  perform private.sync_overbook_request_for_booking(v_booking.id);

  if v_was_booked then
    perform private.promote_slot_waitlist(v_booking.slot_id);
  end if;

  return v_booking;
end;
$function$;

create or replace function private.promote_slot_waitlist(
  p_slot_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_capacity integer;
  v_booked_count integer;
  v_booking_id uuid;
begin
  perform 1
  from public.class_slots
  where id = p_slot_id
  for update;

  if not found then
    return null;
  end if;

  v_capacity := private.effective_slot_capacity(p_slot_id);

  select count(*)::integer
  into v_booked_count
  from public.bookings
  where slot_id = p_slot_id
    and status = 'booked'::public.booking_status;

  if v_capacity is not null and v_booked_count >= v_capacity then
    return null;
  end if;

  select b.id
  into v_booking_id
  from public.bookings b
  where b.slot_id = p_slot_id
    and b.status = 'waitlisted'::public.booking_status
  order by b.booked_at, b.id
  for update skip locked
  limit 1;

  if v_booking_id is null then
    return null;
  end if;

  update public.bookings
  set status = 'booked'::public.booking_status
  where id = v_booking_id;

  perform private.sync_overbook_request_for_booking(v_booking_id);

  return v_booking_id;
end;
$function$;

create or replace function public.review_overbook_request(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null::text
)
returns public.overbook_requests
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_request public.overbook_requests%rowtype;
  v_reviewer uuid := private.current_dancer_id();
begin
  if v_reviewer is null then
    raise exception 'dancer profile not found' using errcode='P0002';
  end if;

  if p_approve is null then
    raise exception 'approval decision is required' using errcode='22023';
  end if;

  select *
  into v_request
  from public.overbook_requests
  where id = p_request_id;

  if not found then
    raise exception 'overbook request not found' using errcode='P0002';
  end if;

  if not private.can_operate_slot(v_request.slot_id) then
    raise exception 'trainer or administrator role required'
      using errcode='42501';
  end if;

  if v_request.status <> 'pending'::public.overbook_request_status then
    raise exception 'overbook request is not pending'
      using errcode='23514';
  end if;

  if p_approve then
    update public.bookings b
    set status = 'booked'::public.booking_status
    where b.id = v_request.booking_id
      and b.status = 'waitlisted'::public.booking_status;

    if not found then
      raise exception 'booking is no longer waitlisted'
        using errcode='23514';
    end if;

    update public.overbook_requests
    set status = 'approved'::public.overbook_request_status,
        reviewed_at = now(),
        reviewed_by = v_reviewer,
        review_note = nullif(btrim(p_note), '')
    where id = p_request_id
    returning * into v_request;
  else
    update public.overbook_requests
    set status = 'rejected'::public.overbook_request_status,
        reviewed_at = now(),
        reviewed_by = v_reviewer,
        review_note = nullif(btrim(p_note), '')
    where id = p_request_id
    returning * into v_request;
  end if;

  return v_request;
end;
$function$;

revoke all on function public.review_overbook_request(uuid, boolean, text) from public;
revoke all on function public.review_overbook_request(uuid, boolean, text) from anon;
grant execute on function public.review_overbook_request(uuid, boolean, text) to authenticated;

create or replace function public.get_pending_overbook_requests()
returns table(
  request_id uuid,
  booking_id uuid,
  slot_id uuid,
  dancer_id uuid,
  dancer_name text,
  group_id uuid,
  group_title text,
  starts_at timestamptz,
  requested_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select
    r.id,
    r.booking_id,
    r.slot_id,
    r.dancer_id,
    coalesce(
      nullif(d.custom_name, ''),
      nullif(concat_ws(' ', d.first_name, d.last_name), ''),
      d.telegram_username,
      'Dancer'
    ) as dancer_name,
    cs.group_id,
    g.title,
    cs.starts_at,
    r.requested_at
  from public.overbook_requests r
  join public.bookings b on b.id = r.booking_id
  join public.class_slots cs on cs.id = r.slot_id
  join public.dance_group g on g.id = cs.group_id
  join public.dancer d on d.id = r.dancer_id
  where r.status = 'pending'::public.overbook_request_status
    and b.status = 'waitlisted'::public.booking_status
    and private.can_operate_slot(r.slot_id)
  order by r.requested_at, r.id
$function$;

revoke all on function public.get_pending_overbook_requests() from public;
revoke all on function public.get_pending_overbook_requests() from anon;
grant execute on function public.get_pending_overbook_requests() to authenticated;
