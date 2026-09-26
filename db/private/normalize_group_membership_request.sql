-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: normalize_group_membership_request
-- Updated:  2026-09-26T20:34:08.898Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.normalize_group_membership_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_group public.dance_group%rowtype;
begin
  select *
  into v_group
  from public.dance_group
  where id = new.group_id;

  if not found
    or not v_group.active
    or v_group.enrollment_status in ('closed','archived')
  then
    raise exception 'group is not accepting membership requests'
      using errcode='23514';
  end if;

  new.dancer_id := private.current_dancer_id();
  if new.dancer_id is null then
    raise exception 'dancer profile not found' using errcode='P0002';
  end if;

  new.requested_at := now();
  new.approved_at := null;
  new.approved_by := null;
  new.ends_at := null;

  if v_group.approval_required
    or v_group.enrollment_status = 'waitlist_only'
  then
    new.status := 'pending';
    new.starts_at := null;
  else
    new.status := 'active';
    new.starts_at := now();
  end if;

  return new;
end;
$function$
