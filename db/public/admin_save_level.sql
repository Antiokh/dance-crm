-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_save_level
-- Updated:  2026-09-27T08:52:03.136Z

-- overload
-- language: sql
-- args: p_level_id bigint, p_payload jsonb
-- returns: bigint

CREATE OR REPLACE FUNCTION public.admin_save_level(p_level_id bigint, p_payload jsonb)
 RETURNS bigint
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.admin_save_level_internal(p_level_id,p_payload)
$function$
