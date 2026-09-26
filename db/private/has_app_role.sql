-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: has_app_role
-- Updated:  2026-09-26T20:34:00.557Z

-- overload
-- language: sql
-- args: p_role app_role
-- returns: boolean

CREATE OR REPLACE FUNCTION private.has_app_role(p_role app_role)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.dancer_app_roles r
    join public.dancer d on d.id = r.dancer_id
    where d.auth_user_id = auth.uid()
      and r.role = p_role
  )
$function$
