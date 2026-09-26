-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: validate_class_schedule
-- Updated:  2026-09-26T20:34:11.530Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.validate_class_schedule()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (
    select 1
    from pg_catalog.pg_timezone_names
    where name = new.timezone
  ) then
    raise exception 'invalid timezone: %', new.timezone
      using errcode='22023';
  end if;

  if new.venue_id is not null and not exists (
    select 1
    from public.venues v
    where v.id = new.venue_id
      and v.active
  ) then
    raise exception 'venue is inactive or missing'
      using errcode='23514';
  end if;

  return new;
end;
$function$
