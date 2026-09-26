-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_issue_subscription
-- Updated:  2026-09-26T20:34:37.701Z

-- overload
-- language: sql
-- args: p_dancer_id uuid, p_plan_id uuid, p_starts_at timestamp with time zone DEFAULT now(), p_included_classes_override integer DEFAULT NULL::integer, p_allowed_skips_override integer DEFAULT NULL::integer, p_validity_days_override integer DEFAULT NULL::integer, p_style_ids_override smallint[] DEFAULT NULL::smallint[], p_group_ids_override uuid[] DEFAULT NULL::uuid[]
-- returns: uuid

CREATE OR REPLACE FUNCTION public.admin_issue_subscription(p_dancer_id uuid, p_plan_id uuid, p_starts_at timestamp with time zone DEFAULT now(), p_included_classes_override integer DEFAULT NULL::integer, p_allowed_skips_override integer DEFAULT NULL::integer, p_validity_days_override integer DEFAULT NULL::integer, p_style_ids_override smallint[] DEFAULT NULL::smallint[], p_group_ids_override uuid[] DEFAULT NULL::uuid[])
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.admin_issue_subscription(
    p_dancer_id,
    p_plan_id,
    p_starts_at,
    p_included_classes_override,
    p_allowed_skips_override,
    p_validity_days_override,
    p_style_ids_override,
    p_group_ids_override
  )
$function$
