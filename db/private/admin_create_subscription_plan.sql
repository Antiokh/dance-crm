-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: admin_create_subscription_plan
-- Updated:  2026-09-26T20:33:55.255Z

-- overload
-- language: plpgsql
-- args: p_name text, p_description text, p_renewal_mode subscription_renewal_mode, p_usage_mode subscription_usage_mode, p_included_classes integer, p_validity_days integer, p_allowed_skips integer DEFAULT 0, p_replacement_grace_days integer DEFAULT 0, p_style_ids smallint[] DEFAULT '{}'::smallint[], p_group_ids uuid[] DEFAULT '{}'::uuid[]
-- returns: uuid

CREATE OR REPLACE FUNCTION private.admin_create_subscription_plan(p_name text, p_description text, p_renewal_mode subscription_renewal_mode, p_usage_mode subscription_usage_mode, p_included_classes integer, p_validity_days integer, p_allowed_skips integer DEFAULT 0, p_replacement_grace_days integer DEFAULT 0, p_style_ids smallint[] DEFAULT '{}'::smallint[], p_group_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_plan_id uuid;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  insert into public.subscription_plans (
    name,
    description,
    renewal_mode,
    usage_mode,
    included_classes,
    validity_days,
    allowed_skips,
    replacement_grace_days
  )
  values (
    btrim(p_name),
    nullif(btrim(p_description), ''),
    p_renewal_mode,
    p_usage_mode,
    case
      when p_usage_mode='unlimited'::public.subscription_usage_mode
        then null
      else p_included_classes
    end,
    p_validity_days,
    coalesce(p_allowed_skips, 0),
    coalesce(p_replacement_grace_days, 0)
  )
  returning id into v_plan_id;

  insert into public.subscription_plan_styles(plan_id, style_id)
  select v_plan_id, unnest(coalesce(p_style_ids, '{}'::smallint[]))
  on conflict do nothing;

  insert into public.subscription_plan_groups(plan_id, group_id)
  select v_plan_id, unnest(coalesce(p_group_ids, '{}'::uuid[]))
  on conflict do nothing;

  return v_plan_id;
end;
$function$
