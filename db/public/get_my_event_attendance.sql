-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_my_event_attendance
-- Updated:  2026-09-27T01:01:00.845Z

-- overload
-- language: sql
-- args: 
-- returns: TABLE(event_id uuid)

CREATE OR REPLACE FUNCTION public.get_my_event_attendance()
 RETURNS TABLE(event_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select ea.event_id
  from public.event_attendance ea
  where ea.dancer_id = private.current_dancer_id()
    and ea.cancelled_at is null
  order by ea.event_id
$function$
