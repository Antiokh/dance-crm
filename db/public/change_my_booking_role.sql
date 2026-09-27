-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: change_my_booking_role
-- Updated:  2026-09-27T06:52:00.336Z

-- overload
-- language: sql
-- args: p_booking_id uuid, p_dance_role_id smallint
-- returns: bookings

CREATE OR REPLACE FUNCTION public.change_my_booking_role(p_booking_id uuid, p_dance_role_id smallint)
 RETURNS bookings
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.change_my_booking_role_internal(
    p_booking_id,
    p_dance_role_id
  )
$function$
