-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: materialize_class_schedule
-- Updated:  2026-09-26T20:35:26.864Z

-- overload
-- language: sql
-- args: p_schedule_id uuid, p_through_date date DEFAULT (CURRENT_DATE + 56)
-- returns: integer

CREATE OR REPLACE FUNCTION public.materialize_class_schedule(p_schedule_id uuid, p_through_date date DEFAULT (CURRENT_DATE + 56))
 RETURNS integer
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.materialize_class_schedule(
    p_schedule_id,
    p_through_date
  )
$function$
