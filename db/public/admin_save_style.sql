-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_save_style
-- Updated:  2026-09-27T08:52:01.783Z

-- overload
-- language: sql
-- args: p_style_id smallint, p_payload jsonb
-- returns: smallint

CREATE OR REPLACE FUNCTION public.admin_save_style(p_style_id smallint, p_payload jsonb)
 RETURNS smallint
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.admin_save_style_internal(p_style_id,p_payload)
$function$
