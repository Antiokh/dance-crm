-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: operator_cancel_booking
-- Updated:  2026-09-26T20:34:29.556Z

-- overload
-- language: sql
-- args: p_booking_id uuid
-- returns: bookings

CREATE OR REPLACE FUNCTION public.operator_cancel_booking(p_booking_id uuid)
 RETURNS bookings
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.operator_cancel_booking_internal(p_booking_id)
$function$
