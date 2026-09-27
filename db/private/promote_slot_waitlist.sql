-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: promote_slot_waitlist
-- Updated:  2026-09-27T01:11:00.493Z

-- overload
-- language: plpgsql
-- args: p_slot_id uuid
-- returns: uuid

CREATE OR REPLACE FUNCTION private.promote_slot_waitlist(p_slot_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_capacity integer;
  v_booked_count integer;
  v_booking_id uuid;
begin
  perform 1
  from public.class_slots
  where id = p_slot_id
  for update;

  if not found then
    return null;
  end if;

  v_capacity := private.effective_slot_capacity(p_slot_id);

  select count(*)::integer
  into v_booked_count
  from public.bookings
  where slot_id = p_slot_id
    and status = 'booked'::public.booking_status;

  if v_capacity is not null and v_booked_count >= v_capacity then
    return null;
  end if;

  select b.id
  into v_booking_id
  from public.bookings b
  where b.slot_id = p_slot_id
    and b.status = 'waitlisted'::public.booking_status
  order by b.booked_at, b.id
  for update skip locked
  limit 1;

  if v_booking_id is null then
    return null;
  end if;

  update public.bookings
  set status = 'booked'::public.booking_status
  where id = v_booking_id;

  perform private.sync_overbook_request_for_booking(v_booking_id);

  return v_booking_id;
end;
$function$
