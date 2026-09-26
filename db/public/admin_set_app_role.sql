-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_set_app_role
-- Updated:  2026-09-26T20:35:25.480Z

-- overload
-- language: sql
-- args: p_dancer_id uuid, p_role app_role, p_enabled boolean
-- returns: void

CREATE OR REPLACE FUNCTION public.admin_set_app_role(p_dancer_id uuid, p_role app_role, p_enabled boolean)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.admin_set_app_role(p_dancer_id, p_role, p_enabled)
$function$
