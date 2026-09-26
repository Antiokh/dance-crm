-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: mark_booking_attendance
-- Updated:  2026-09-26T20:34:30.732Z

-- overload
-- language: sql
-- args: p_booking_id uuid, p_attendance_status attendance_status
-- returns: bookings

CREATE OR REPLACE FUNCTION public.mark_booking_attendance(p_booking_id uuid, p_attendance_status attendance_status)
 RETURNS bookings
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.mark_booking_attendance_internal(
    p_booking_id,
    p_attendance_status
  )
$function$
