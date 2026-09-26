-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: admin_cancel_subscription
-- Updated:  2026-09-26T20:33:54.031Z

-- overload
-- language: plpgsql
-- args: p_subscription_id uuid, p_reason text DEFAULT NULL::text
-- returns: void

CREATE OR REPLACE FUNCTION private.admin_cancel_subscription(p_subscription_id uuid, p_reason text DEFAULT NULL::text)
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

  update public.student_subscriptions
  set status='cancelled'::public.student_subscription_status,
      cancelled_at=now(),
      cancellation_reason=nullif(btrim(p_reason), '')
  where id=p_subscription_id
    and status='active'::public.student_subscription_status;

  if not found then
    raise exception 'active subscription not found'
      using errcode='P0002';
  end if;
end;
$function$
