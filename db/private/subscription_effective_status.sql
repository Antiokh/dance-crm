-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: subscription_effective_status
-- Updated:  2026-09-26T20:33:49.354Z

-- overload
-- language: plpgsql
-- args: p_subscription_id uuid
-- returns: text

CREATE OR REPLACE FUNCTION private.subscription_effective_status(p_subscription_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_subscription public.student_subscriptions%rowtype;
  v_balance jsonb;
  v_class_balance integer;
begin
  select *
  into v_subscription
  from public.student_subscriptions
  where id = p_subscription_id;

  if not found then
    return null;
  end if;

  if v_subscription.status='cancelled'::public.student_subscription_status then
    return 'cancelled';
  end if;

  if v_subscription.starts_at > now() then
    return 'scheduled';
  end if;

  if v_subscription.ends_at is not null
    and v_subscription.ends_at < now()
  then
    return 'expired';
  end if;

  if v_subscription.usage_mode_snapshot='credits'::public.subscription_usage_mode then
    v_balance := private.subscription_balance(p_subscription_id);
    v_class_balance := coalesce((v_balance->>'class_balance')::integer, 0);

    if v_class_balance <= 0 then
      return 'exhausted';
    end if;
  end if;

  return 'active';
end;
$function$
