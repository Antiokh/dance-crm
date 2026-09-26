-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: cancel_class_slot
-- Updated:  2026-09-26T20:35:35.428Z

-- overload
-- language: sql
-- args: p_slot_id uuid, p_reason text DEFAULT NULL::text
-- returns: class_slots

CREATE OR REPLACE FUNCTION public.cancel_class_slot(p_slot_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS class_slots
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.cancel_class_slot_for_operator(p_slot_id, p_reason)
$function$
