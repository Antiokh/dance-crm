-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: set_generated_group_title
-- Updated:  2026-09-27T07:41:03.929Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.set_generated_group_title()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  new.title := private.group_generated_title(
    new.id,
    new.style_id,
    new.level_id
  );
  return new;
end;
$function$
