-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: operator_cancel_booking_internal
-- Updated:  2026-09-26T20:33:40.180Z

-- overload
-- language: plpgsql
-- args: p_booking_id uuid
-- returns: bookings

CREATE OR REPLACE FUNCTION private.operator_cancel_booking_internal(p_booking_id uuid)
 RETURNS bookings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_booking public.bookings%rowtype;
  v_was_booked boolean;
  v_type public.booking_cancellation_type;
begin
  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'booking not found'
      using errcode='P0002';
  end if;

  if not private.can_operate_slot(v_booking.slot_id) then
    raise exception 'booking access denied'
      using errcode='42501';
  end if;

  if v_booking.status = 'cancelled'::public.booking_status then
    return v_booking;
  end if;

  v_was_booked := v_booking.status = 'booked'::public.booking_status;

  if private.has_app_role('administrator'::public.app_role) then
    v_type := 'administrator'::public.booking_cancellation_type;
  else
    v_type := 'trainer'::public.booking_cancellation_type;
  end if;

  update public.bookings
  set status = 'cancelled'::public.booking_status,
      cancelled_at = now(),
      cancellation_type = v_type
  where id = p_booking_id
  returning * into v_booking;

  if v_was_booked then
    perform private.promote_slot_waitlist(v_booking.slot_id);
  end if;

  return v_booking;
end;
$function$
