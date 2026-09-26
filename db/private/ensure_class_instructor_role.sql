-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: ensure_class_instructor_role
-- Updated:  2026-09-26T20:34:13.011Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.ensure_class_instructor_role()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (
    select 1
    from public.dancer_app_roles r
    where r.dancer_id = new.trainer_id
      and r.role = 'trainer'::public.app_role
  ) then
    raise exception 'assigned dancer does not have trainer role'
      using errcode='23514';
  end if;

  return new;
end;
$function$
