-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: can_view_class
-- Updated:  2026-09-26T20:34:15.643Z

-- overload
-- language: sql
-- args: p_group_id uuid, p_visibility class_visibility
-- returns: boolean

CREATE OR REPLACE FUNCTION private.can_view_class(p_group_id uuid, p_visibility class_visibility)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    when private.can_manage_group(p_group_id) then true
    when p_visibility = 'hidden'::public.class_visibility then false
    when p_visibility = 'members'::public.class_visibility
      then private.has_active_group_membership(p_group_id)
    else private.can_view_group(p_group_id)
  end
$function$
