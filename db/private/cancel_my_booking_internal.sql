-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: cancel_my_booking_internal
-- Updated:  2026-09-26T20:33:38.685Z

-- overload
-- language: plpgsql
-- args: p_booking_id uuid
-- returns: bookings

CREATE OR REPLACE FUNCTION private.cancel_my_booking_internal(p_booking_id uuid)
 RETURNS bookings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  if v_was_booked then
    perform private.promote_slot_waitlist(v_booking.slot_id);
  end if;

  return v_booking;
end;
$function$
