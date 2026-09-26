-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_cancel_subscription
-- Updated:  2026-09-26T20:34:40.273Z

-- overload
-- language: sql
-- args: p_subscription_id uuid, p_reason text DEFAULT NULL::text
-- returns: void

CREATE OR REPLACE FUNCTION public.admin_cancel_subscription(p_subscription_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.admin_cancel_subscription(
    p_subscription_id,
    p_reason
  )
$function$
