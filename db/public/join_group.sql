-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: join_group
-- Updated:  2026-09-26T20:35:22.595Z

-- overload
-- language: plpgsql
-- args: p_group_id uuid
-- returns: group_memberships

CREATE OR REPLACE FUNCTION public.join_group(p_group_id uuid)
 RETURNS group_memberships
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_membership public.group_memberships;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode='P0002';
  end if;

  insert into public.group_memberships (group_id, dancer_id)
  values (p_group_id, v_dancer_id)
  returning * into v_membership;

  return v_membership;
exception
  when unique_violation then
    raise exception 'membership request already exists'
      using errcode='23505';
end;
$function$
