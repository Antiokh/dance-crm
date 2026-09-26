-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: can_manage_group
-- Updated:  2026-09-26T20:34:05.733Z

-- overload
-- language: sql
-- args: p_group_id uuid
-- returns: boolean

CREATE OR REPLACE FUNCTION private.can_manage_group(p_group_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    private.has_app_role('administrator'::public.app_role)
    or private.is_group_trainer(p_group_id)
$function$
