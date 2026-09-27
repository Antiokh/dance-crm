-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: default_dance_role_for_style
-- Updated:  2026-09-27T07:21:01.634Z

-- overload
-- language: sql
-- args: p_dancer_id uuid, p_style_id smallint
-- returns: smallint

CREATE OR REPLACE FUNCTION private.default_dance_role_for_style(p_dancer_id uuid, p_style_id smallint)
 RETURNS smallint
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(
    (
      select case when p.is_leader then 1::smallint else 2::smallint end
      from public.dancer_style_profile p
      where p.dancer_id = p_dancer_id
        and p.style_id = p_style_id
      order by p.is_default desc, p.created_at, p.id
      limit 1
    ),
    (
      select d.primary_role
      from public.dancer d
      where d.id = p_dancer_id
    )
  )
$function$
