-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: cancel_class_slot_for_operator
-- Updated:  2026-09-26T20:33:30.471Z

-- overload
-- language: plpgsql
-- args: p_slot_id uuid, p_reason text DEFAULT NULL::text
-- returns: class_slots

CREATE OR REPLACE FUNCTION private.cancel_class_slot_for_operator(p_slot_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS class_slots
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_slot public.class_slots;
begin
  if not (
    private.has_app_role('administrator'::public.app_role)
    or private.can_operate_slot(p_slot_id)
  ) then
    raise exception 'class slot access denied'
      using errcode='42501';
  end if;

  update public.class_slots
  set status = 'cancelled'::public.class_slot_status,
      cancelled_at = now(),
      cancellation_reason = nullif(btrim(p_reason), '')
  where id = p_slot_id
    and status = 'scheduled'::public.class_slot_status
  returning * into v_slot;

  if not found then
    raise exception 'scheduled class slot not found'
      using errcode='P0002';
  end if;

  return v_slot;
end;
$function$
