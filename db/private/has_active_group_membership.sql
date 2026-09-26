-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: has_active_group_membership
-- Updated:  2026-09-26T20:34:14.251Z

-- overload
-- language: sql
-- args: p_group_id uuid
-- returns: boolean

CREATE OR REPLACE FUNCTION private.has_active_group_membership(p_group_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.group_memberships gm
    where gm.group_id = p_group_id
      and gm.dancer_id = private.current_dancer_id()
      and gm.status = 'active'::public.group_membership_status
      and (gm.starts_at is null or gm.starts_at <= now())
      and (gm.ends_at is null or gm.ends_at >= now())
  )
$function$
