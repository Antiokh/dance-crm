-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: validate_dancer_style_training_level
-- Updated:  2026-09-27T08:01:03.898Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.validate_dancer_style_training_level()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.training_level_id is null then return new; end if;

  if not exists (
    select 1
    from public.styles_levels l
    where l.id=new.training_level_id
      and l.style_id=new.style_id
      and l.kind='training'
  ) then
    raise exception 'training level must belong to the same style and be kind=training'
      using errcode='23514';
  end if;

  return new;
end;
$function$
