-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: refresh_group_titles_from_dancer
-- Updated:  2026-09-27T07:41:07.977Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.refresh_group_titles_from_dancer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_group_id uuid;
begin
  if new.custom_name is not distinct from old.custom_name
    and new.first_name is not distinct from old.first_name
    and new.last_name is not distinct from old.last_name
    and new.telegram_username is not distinct from old.telegram_username
  then
    return null;
  end if;

  for v_group_id in
    select gt.group_id
    from public.group_trainers gt
    where gt.trainer_id = new.id
      and gt.trainer_role = 'lead'::public.group_trainer_role
  loop
    perform private.refresh_group_title(v_group_id);
  end loop;

  return null;
end;
$function$
