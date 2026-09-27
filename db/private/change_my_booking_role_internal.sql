-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: change_my_booking_role_internal
-- Updated:  2026-09-27T06:51:07.050Z

-- overload
-- language: plpgsql
-- args: p_booking_id uuid, p_dance_role_id smallint
-- returns: bookings

CREATE OR REPLACE FUNCTION private.change_my_booking_role_internal(p_booking_id uuid, p_dance_role_id smallint)
 RETURNS bookings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_booking public.bookings%rowtype;
  v_slot record;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode='P0002';
  end if;

  if p_dance_role_id is null then
    raise exception 'dance role is required' using errcode='22023';
  end if;

  select *
  into v_booking
  from public.bookings b
  where b.id = p_booking_id
    and b.dancer_id = v_dancer_id
  for update;

  if not found then
    raise exception 'booking not found' using errcode='P0002';
  end if;

  if v_booking.status = 'cancelled'::public.booking_status then
    raise exception 'cancelled booking role cannot be changed' using errcode='23514';
  end if;

  select cs.starts_at, g.style_id, s.is_partner_dance
  into v_slot
  from public.class_slots cs
  join public.dance_group g on g.id = cs.group_id
  join public.l_dance_style s on s.id = g.style_id
  where cs.id = v_booking.slot_id;

  if not found then
    raise exception 'class slot not found' using errcode='P0002';
  end if;

  if v_slot.starts_at <= now() then
    raise exception 'class slot has already started' using errcode='23514';
  end if;

  if not coalesce(v_slot.is_partner_dance, true) then
    raise exception 'dance role is not used for this style' using errcode='23514';
  end if;

  if not exists (
    select 1
    from public.l_dance_role r
    where r.id = p_dance_role_id
  ) then
    raise exception 'dance role not found' using errcode='23514';
  end if;

  if not private.dancer_can_use_role_for_style(
    v_dancer_id,
    v_slot.style_id,
    p_dance_role_id
  ) then
    raise exception 'dance role is not enabled for this style'
      using errcode='23514';
  end if;

  update public.bookings
  set dance_role_id = p_dance_role_id
  where id = p_booking_id
  returning * into v_booking;

  return v_booking;
end;
$function$
