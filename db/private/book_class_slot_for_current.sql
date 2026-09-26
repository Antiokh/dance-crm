-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: book_class_slot_for_current
-- Updated:  2026-09-26T20:33:37.366Z

-- overload
-- language: plpgsql
-- args: p_slot_id uuid, p_dance_role_id smallint DEFAULT NULL::smallint
-- returns: bookings

CREATE OR REPLACE FUNCTION private.book_class_slot_for_current(p_slot_id uuid, p_dance_role_id smallint DEFAULT NULL::smallint)
 RETURNS bookings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  return v_booking;
end;
$function$
