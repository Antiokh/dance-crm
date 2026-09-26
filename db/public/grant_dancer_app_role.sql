-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: grant_dancer_app_role
-- Updated:  2026-09-26T20:35:11.848Z

-- overload
-- language: plpgsql
-- args: p_dancer_id uuid, p_role app_role, p_granted_by uuid DEFAULT NULL::uuid
-- returns: void

CREATE OR REPLACE FUNCTION public.grant_dancer_app_role(p_dancer_id uuid, p_role app_role, p_granted_by uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into public.dancer_app_roles (dancer_id, role, granted_by)
  values (p_dancer_id, p_role, p_granted_by)
  on conflict (dancer_id, role) do update
  set granted_at = now(),
      granted_by = excluded.granted_by;
end;
$function$
