-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: refresh_class_slot_role_counts
-- Updated:  2026-09-27T01:21:03.489Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.refresh_class_slot_role_counts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    perform private.recount_class_slot_role_counts(old.slot_id);
    return old;
  end if;

  perform private.recount_class_slot_role_counts(new.slot_id);

  if tg_op = 'UPDATE'
    and old.slot_id is distinct from new.slot_id
  then
    perform private.recount_class_slot_role_counts(old.slot_id);
  end if;

  return new;
end;
$function$
