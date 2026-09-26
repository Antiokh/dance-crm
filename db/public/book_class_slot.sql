-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: book_class_slot
-- Updated:  2026-09-26T20:34:25.413Z

-- overload
-- language: sql
-- args: p_slot_id uuid, p_dance_role_id smallint DEFAULT NULL::smallint
-- returns: bookings

CREATE OR REPLACE FUNCTION public.book_class_slot(p_slot_id uuid, p_dance_role_id smallint DEFAULT NULL::smallint)
 RETURNS bookings
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.book_class_slot_for_current(
    p_slot_id,
    p_dance_role_id
  )
$function$
