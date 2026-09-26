-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: cancel_my_booking
-- Updated:  2026-09-26T20:34:28.141Z

-- overload
-- language: sql
-- args: p_booking_id uuid
-- returns: bookings

CREATE OR REPLACE FUNCTION public.cancel_my_booking(p_booking_id uuid)
 RETURNS bookings
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.cancel_my_booking_internal(p_booking_id)
$function$
