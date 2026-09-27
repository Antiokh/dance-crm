-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: dancer_can_use_role_for_style
-- Updated:  2026-09-27T07:21:05.642Z

-- overload
-- language: sql
-- args: p_dancer_id uuid, p_style_id smallint, p_role_id smallint
-- returns: boolean

CREATE OR REPLACE FUNCTION private.dancer_can_use_role_for_style(p_dancer_id uuid, p_style_id smallint, p_role_id smallint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select case
    when p_role_id not in (1, 2) then false
    when exists (
      select 1
      from public.dancer_style_profile p
      where p.dancer_id = p_dancer_id
        and p.style_id = p_style_id
    )
    then exists (
      select 1
      from public.dancer_style_profile p
      where p.dancer_id = p_dancer_id
        and p.style_id = p_style_id
        and p.is_leader = (p_role_id = 1)
    )
    else p_role_id = private.default_dance_role_for_style(
      p_dancer_id,
      p_style_id
    )
  end
$function$
