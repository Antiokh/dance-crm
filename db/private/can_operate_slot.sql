-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: can_operate_slot
-- Updated:  2026-09-26T20:34:18.380Z

-- overload
-- language: sql
-- args: p_slot_id uuid
-- returns: boolean

CREATE OR REPLACE FUNCTION private.can_operate_slot(p_slot_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.class_slots cs
    where cs.id = p_slot_id
      and (
        private.has_app_role('administrator'::public.app_role)
        or private.is_group_trainer(cs.group_id)
        or private.is_slot_instructor(cs.id)
      )
  )
$function$
