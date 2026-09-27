-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_save_dancer
-- Updated:  2026-09-27T08:52:00.484Z

-- overload
-- language: sql
-- args: p_dancer_id uuid, p_payload jsonb
-- returns: uuid

CREATE OR REPLACE FUNCTION public.admin_save_dancer(p_dancer_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.admin_save_dancer_internal(p_dancer_id,p_payload)
$function$
