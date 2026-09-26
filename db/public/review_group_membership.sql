-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: review_group_membership
-- Updated:  2026-09-26T20:35:23.995Z

-- overload
-- language: plpgsql
-- args: p_membership_id uuid, p_approve boolean
-- returns: group_memberships

CREATE OR REPLACE FUNCTION public.review_group_membership(p_membership_id uuid, p_approve boolean)
 RETURNS group_memberships
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.current_dancer_id();
  v_membership public.group_memberships;
begin
  update public.group_memberships gm
  set status = case
        when p_approve then 'active'::public.group_membership_status
        else 'rejected'::public.group_membership_status
      end,
      approved_at = now(),
      approved_by = v_actor,
      starts_at = case when p_approve then coalesce(gm.starts_at, now()) else gm.starts_at end,
      ends_at = case when p_approve then null else coalesce(gm.ends_at, now()) end
  where gm.id = p_membership_id
    and gm.status = 'pending'
    and private.can_manage_group(gm.group_id)
  returning * into v_membership;

  if not found then
    raise exception 'pending membership not found or access denied'
      using errcode='P0002';
  end if;

  return v_membership;
end;
$function$
