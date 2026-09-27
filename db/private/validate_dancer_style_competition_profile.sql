-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: validate_dancer_style_competition_profile
-- Updated:  2026-09-27T08:01:05.158Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.validate_dancer_style_competition_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_style_id smallint;
begin
  select p.style_id into v_style_id
  from public.dancer_style_profile p
  where p.id=new.style_profile_id;

  if v_style_id is null then
    raise exception 'style profile not found' using errcode='23503';
  end if;

  if not exists (
    select 1
    from public.styles_levels l
    where l.id=new.level_id
      and l.style_id=v_style_id
      and l.kind='competition'
      and l.system_code=new.system_code
  ) then
    raise exception 'competition level must match style and system'
      using errcode='23514';
  end if;

  return new;
end;
$function$
