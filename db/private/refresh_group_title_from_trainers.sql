-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: refresh_group_title_from_trainers
-- Updated:  2026-09-27T07:41:06.662Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.refresh_group_title_from_trainers()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op <> 'INSERT' then
    perform private.refresh_group_title(old.group_id);
  end if;

  if tg_op <> 'DELETE' then
    perform private.refresh_group_title(new.group_id);
  end if;

  return null;
end;
$function$
