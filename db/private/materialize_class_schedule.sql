-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: materialize_class_schedule
-- Updated:  2026-09-27T00:31:04.345Z

-- overload
-- language: plpgsql
-- args: p_schedule_id uuid, p_through_date date
-- returns: integer

CREATE OR REPLACE FUNCTION private.materialize_class_schedule(p_schedule_id uuid, p_through_date date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  if private.ensure_next_class_slot(p_schedule_id) then
    return 1;
  end if;

  return 0;
end;
$function$
