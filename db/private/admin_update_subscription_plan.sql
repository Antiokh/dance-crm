-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: admin_update_subscription_plan
-- Updated:  2026-09-26T20:33:52.744Z

-- overload
-- language: plpgsql
-- args: p_plan_id uuid, p_name text, p_description text, p_renewal_mode subscription_renewal_mode, p_usage_mode subscription_usage_mode, p_included_classes integer, p_validity_days integer, p_allowed_skips integer, p_replacement_grace_days integer, p_active boolean, p_style_ids smallint[], p_group_ids uuid[]
-- returns: void

CREATE OR REPLACE FUNCTION private.admin_update_subscription_plan(p_plan_id uuid, p_name text, p_description text, p_renewal_mode subscription_renewal_mode, p_usage_mode subscription_usage_mode, p_included_classes integer, p_validity_days integer, p_allowed_skips integer, p_replacement_grace_days integer, p_active boolean, p_style_ids smallint[], p_group_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  update public.subscription_plans
  set name = btrim(p_name),
      description = nullif(btrim(p_description), ''),
      renewal_mode = p_renewal_mode,
      usage_mode = p_usage_mode,
      included_classes = case
        when p_usage_mode='unlimited'::public.subscription_usage_mode
          then null
        else p_included_classes
      end,
      validity_days = p_validity_days,
      allowed_skips = coalesce(p_allowed_skips, 0),
      replacement_grace_days = coalesce(p_replacement_grace_days, 0),
      active = p_active
  where id = p_plan_id;

  if not found then
    raise exception 'subscription plan not found'
      using errcode='P0002';
  end if;

  delete from public.subscription_plan_styles
  where plan_id = p_plan_id;

  delete from public.subscription_plan_groups
  where plan_id = p_plan_id;

  insert into public.subscription_plan_styles(plan_id, style_id)
  select p_plan_id, unnest(coalesce(p_style_ids, '{}'::smallint[]))
  on conflict do nothing;

  insert into public.subscription_plan_groups(plan_id, group_id)
  select p_plan_id, unnest(coalesce(p_group_ids, '{}'::uuid[]))
  on conflict do nothing;
end;
$function$
