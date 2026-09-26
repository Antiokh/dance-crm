-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: mark_booking_attendance_internal
-- Updated:  2026-09-26T20:33:41.553Z

-- overload
-- language: plpgsql
-- args: p_booking_id uuid, p_attendance_status attendance_status
-- returns: bookings

CREATE OR REPLACE FUNCTION private.mark_booking_attendance_internal(p_booking_id uuid, p_attendance_status attendance_status)
 RETURNS bookings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_booking public.bookings%rowtype;
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

  if v_booking.status <> 'booked'::public.booking_status then
    raise exception 'attendance can only be marked for booked dancers'
      using errcode='23514';
  end if;

  update public.bookings
  set attendance_status = p_attendance_status
  where id = p_booking_id
  returning * into v_booking;

  return v_booking;
end;
$function$
