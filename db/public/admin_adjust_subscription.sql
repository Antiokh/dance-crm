-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_adjust_subscription
-- Updated:  2026-09-26T20:34:38.964Z

-- overload
-- language: sql
-- args: p_subscription_id uuid, p_class_delta integer DEFAULT 0, p_skip_delta integer DEFAULT 0, p_reason text DEFAULT NULL::text
-- returns: uuid

CREATE OR REPLACE FUNCTION public.admin_adjust_subscription(p_subscription_id uuid, p_class_delta integer DEFAULT 0, p_skip_delta integer DEFAULT 0, p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.admin_adjust_subscription(
    p_subscription_id,
    p_class_delta,
    p_skip_delta,
    p_reason
  )
$function$
