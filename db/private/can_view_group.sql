-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: can_view_group
-- Updated:  2026-09-26T20:34:04.404Z

-- overload
-- language: sql
-- args: p_group_id uuid
-- returns: boolean

CREATE OR REPLACE FUNCTION private.can_view_group(p_group_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.dance_group g
    where g.id = p_group_id
      and (
        g.active
        or private.has_app_role('administrator'::public.app_role)
        or private.is_group_trainer(g.id)
      )
  )
$function$
