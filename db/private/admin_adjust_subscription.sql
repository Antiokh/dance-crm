-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: admin_adjust_subscription
-- Updated:  2026-09-26T20:33:58.007Z

-- overload
-- language: plpgsql
-- args: p_subscription_id uuid, p_class_delta integer DEFAULT 0, p_skip_delta integer DEFAULT 0, p_reason text DEFAULT NULL::text
-- returns: uuid

CREATE OR REPLACE FUNCTION private.admin_adjust_subscription(p_subscription_id uuid, p_class_delta integer DEFAULT 0, p_skip_delta integer DEFAULT 0, p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.current_dancer_id();
  v_transaction_id uuid;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  if coalesce(p_class_delta, 0)=0 and coalesce(p_skip_delta, 0)=0 then
    raise exception 'adjustment delta cannot be zero'
      using errcode='22023';
  end if;

  if not exists (
    select 1
    from public.student_subscriptions s
    where s.id = p_subscription_id
  ) then
    raise exception 'subscription not found'
      using errcode='P0002';
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
    p_subscription_id,
    'admin_adjustment'::public.subscription_transaction_type,
    coalesce(p_class_delta, 0),
    coalesce(p_skip_delta, 0),
    nullif(btrim(p_reason), ''),
    v_actor
  )
  returning id into v_transaction_id;

  return v_transaction_id;
end;
$function$
