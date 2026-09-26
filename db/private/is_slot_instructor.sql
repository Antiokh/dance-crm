-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: is_slot_instructor
-- Updated:  2026-09-26T20:34:17.006Z

-- overload
-- language: sql
-- args: p_slot_id uuid
-- returns: boolean

CREATE OR REPLACE FUNCTION private.is_slot_instructor(p_slot_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.class_slot_instructors csi
    where csi.slot_id = p_slot_id
      and csi.trainer_id = private.current_dancer_id()
  )
$function$
