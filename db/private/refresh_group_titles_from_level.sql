-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: refresh_group_titles_from_level
-- Updated:  2026-09-27T07:42:01.772Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.refresh_group_titles_from_level()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_group_id uuid;
begin
  if new.title_en is not distinct from old.title_en
    and new.title_ru is not distinct from old.title_ru
    and new.title_sr is not distinct from old.title_sr
  then
    return null;
  end if;

  for v_group_id in
    select g.id
    from public.dance_group g
    where g.level_id = new.id
      and g.style_id = new.style_id
  loop
    perform private.refresh_group_title(v_group_id);
  end loop;

  return null;
end;
$function$
