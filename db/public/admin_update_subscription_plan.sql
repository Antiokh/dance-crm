-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_update_subscription_plan
-- Updated:  2026-09-26T20:34:34.674Z

-- overload
-- language: sql
-- args: p_plan_id uuid, p_name text, p_description text, p_renewal_mode subscription_renewal_mode, p_usage_mode subscription_usage_mode, p_included_classes integer, p_validity_days integer, p_allowed_skips integer, p_replacement_grace_days integer, p_active boolean, p_style_ids smallint[], p_group_ids uuid[]
-- returns: void

CREATE OR REPLACE FUNCTION public.admin_update_subscription_plan(p_plan_id uuid, p_name text, p_description text, p_renewal_mode subscription_renewal_mode, p_usage_mode subscription_usage_mode, p_included_classes integer, p_validity_days integer, p_allowed_skips integer, p_replacement_grace_days integer, p_active boolean, p_style_ids smallint[], p_group_ids uuid[])
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.admin_update_subscription_plan(
    p_plan_id,
    p_name,
    p_description,
    p_renewal_mode,
    p_usage_mode,
    p_included_classes,
    p_validity_days,
    p_allowed_skips,
    p_replacement_grace_days,
    p_active,
    p_style_ids,
    p_group_ids
  )
$function$
