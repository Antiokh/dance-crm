-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: subscription_balance
-- Updated:  2026-09-26T20:33:48.119Z

-- overload
-- language: sql
-- args: p_subscription_id uuid
-- returns: jsonb

CREATE OR REPLACE FUNCTION private.subscription_balance(p_subscription_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'class_balance',
      case
        when s.usage_mode_snapshot='unlimited'::public.subscription_usage_mode
          then null
        else coalesce(sum(t.class_delta), 0)
      end,
    'skip_balance',
      coalesce(sum(t.skip_delta), 0)
  )
  from public.student_subscriptions s
  left join public.subscription_transactions t
    on t.subscription_id = s.id
  where s.id = p_subscription_id
  group by s.id, s.usage_mode_snapshot
$function$
