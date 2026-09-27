-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_admin_dancers
-- Updated:  2026-09-27T08:51:08.656Z

-- overload
-- language: sql
-- args: 
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.get_admin_dancers()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select private.get_admin_dancers_internal()
$function$
