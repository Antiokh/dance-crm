-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: has_booking_for_slot
-- Updated:  2026-09-26T20:33:46.825Z

-- overload
-- language: sql
-- args: p_slot_id uuid
-- returns: boolean

CREATE OR REPLACE FUNCTION private.has_booking_for_slot(p_slot_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.bookings b
    where b.slot_id = p_slot_id
      and b.dancer_id = private.current_dancer_id()
  )
$function$
