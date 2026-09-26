-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_reschedule_class_slot
-- Updated:  2026-09-26T20:34:24.240Z

-- overload
-- language: plpgsql
-- args: p_slot_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone
-- returns: class_slots

CREATE OR REPLACE FUNCTION public.admin_reschedule_class_slot(p_slot_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone)
 RETURNS class_slots
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_slot public.class_slots;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  if p_ends_at <= p_starts_at then
    raise exception 'class slot end must be after start'
      using errcode='22023';
  end if;

  update public.class_slots
  set starts_at = p_starts_at,
      ends_at = p_ends_at
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
