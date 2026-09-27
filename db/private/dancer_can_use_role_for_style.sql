-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: dancer_can_use_role_for_style
-- Updated:  2026-09-27T06:51:05.698Z

-- overload
-- language: sql
-- args: p_dancer_id uuid, p_style_id smallint, p_role_id smallint
-- returns: boolean

CREATE OR REPLACE FUNCTION private.dancer_can_use_role_for_style(p_dancer_id uuid, p_style_id smallint, p_role_id smallint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    when exists (
      select 1
      from public.dancer_style_roles all_roles
      where all_roles.dancer_id = p_dancer_id
        and all_roles.style_id = p_style_id
    )
    then exists (
      select 1
      from public.dancer_style_roles allowed_role
      where allowed_role.dancer_id = p_dancer_id
        and allowed_role.style_id = p_style_id
        and allowed_role.role_id = p_role_id
    )
    else p_role_id = private.default_dance_role_for_style(
      p_dancer_id,
      p_style_id
    )
  end
$function$
