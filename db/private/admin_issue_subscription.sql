-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: admin_issue_subscription
-- Updated:  2026-09-26T20:33:56.479Z

-- overload
-- language: plpgsql
-- args: p_dancer_id uuid, p_plan_id uuid, p_starts_at timestamp with time zone DEFAULT now(), p_included_classes_override integer DEFAULT NULL::integer, p_allowed_skips_override integer DEFAULT NULL::integer, p_validity_days_override integer DEFAULT NULL::integer, p_style_ids_override smallint[] DEFAULT NULL::smallint[], p_group_ids_override uuid[] DEFAULT NULL::uuid[]
-- returns: uuid

CREATE OR REPLACE FUNCTION private.admin_issue_subscription(p_dancer_id uuid, p_plan_id uuid, p_starts_at timestamp with time zone DEFAULT now(), p_included_classes_override integer DEFAULT NULL::integer, p_allowed_skips_override integer DEFAULT NULL::integer, p_validity_days_override integer DEFAULT NULL::integer, p_style_ids_override smallint[] DEFAULT NULL::smallint[], p_group_ids_override uuid[] DEFAULT NULL::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.current_dancer_id();
  v_plan public.subscription_plans%rowtype;
  v_subscription_id uuid;
  v_included integer;
  v_skips integer;
  v_validity_days integer;
  v_ends_at timestamptz;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  if not exists (
    select 1 from public.dancer d where d.id = p_dancer_id
  ) then
    raise exception 'dancer not found'
      using errcode='P0002';
  end if;

  select *
  into v_plan
  from public.subscription_plans
  where id = p_plan_id
    and active;

  if not found then
    raise exception 'active subscription plan not found'
      using errcode='P0002';
  end if;

  if v_plan.usage_mode='unlimited'::public.subscription_usage_mode then
    v_included := null;
  else
    v_included := coalesce(
      p_included_classes_override,
      v_plan.included_classes
    );

    if v_included is null or v_included <= 0 then
      raise exception 'included classes must be positive'
        using errcode='22023';
    end if;
  end if;

  v_skips := coalesce(
    p_allowed_skips_override,
    v_plan.allowed_skips,
    0
  );

  v_validity_days := coalesce(
    p_validity_days_override,
    v_plan.validity_days
  );

  if v_validity_days is not null and v_validity_days <= 0 then
    raise exception 'validity days must be positive'
      using errcode='22023';
  end if;

  if v_validity_days is null then
    v_ends_at := null;
  else
    v_ends_at := p_starts_at + make_interval(days => v_validity_days);
  end if;

  insert into public.student_subscriptions (
    dancer_id,
    plan_id,
    starts_at,
    ends_at,
    status,
    usage_mode_snapshot,
    included_classes_snapshot,
    allowed_skips_snapshot,
    replacement_grace_days_snapshot,
    issued_by
  )
  values (
    p_dancer_id,
    p_plan_id,
    p_starts_at,
    v_ends_at,
    'active'::public.student_subscription_status,
    v_plan.usage_mode,
    v_included,
    v_skips,
    v_plan.replacement_grace_days,
    v_actor
  )
  returning id into v_subscription_id;

  if p_style_ids_override is null then
    insert into public.student_subscription_styles(
      subscription_id,
      style_id
    )
    select v_subscription_id, ps.style_id
    from public.subscription_plan_styles ps
    where ps.plan_id = p_plan_id;
  else
    insert into public.student_subscription_styles(
      subscription_id,
      style_id
    )
    select v_subscription_id, unnest(p_style_ids_override);
  end if;

  if p_group_ids_override is null then
    insert into public.student_subscription_groups(
      subscription_id,
      group_id
    )
    select v_subscription_id, pg.group_id
    from public.subscription_plan_groups pg
    where pg.plan_id = p_plan_id;
  else
    insert into public.student_subscription_groups(
      subscription_id,
      group_id
    )
    select v_subscription_id, unnest(p_group_ids_override);
  end if;

  insert into public.subscription_transactions (
    subscription_id,
    transaction_type,
    class_delta,
    skip_delta,
    reason,
    created_by
  )
  values (
    v_subscription_id,
    'issue'::public.subscription_transaction_type,
    coalesce(v_included, 0),
    v_skips,
    'Initial entitlement',
    v_actor
  );

  return v_subscription_id;
end;
$function$
