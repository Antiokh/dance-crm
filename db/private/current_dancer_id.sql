-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: current_dancer_id
-- Updated:  2026-09-26T20:33:59.265Z

-- overload
-- language: sql
-- args: 
-- returns: uuid

CREATE OR REPLACE FUNCTION private.current_dancer_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select d.id
  from public.dancer d
  where d.auth_user_id = auth.uid()
  limit 1
$function$
