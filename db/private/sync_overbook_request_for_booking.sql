-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: sync_overbook_request_for_booking
-- Updated:  2026-09-27T01:11:04.476Z

-- overload
-- language: plpgsql
-- args: p_booking_id uuid
-- returns: uuid

CREATE OR REPLACE FUNCTION private.sync_overbook_request_for_booking(p_booking_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_booking public.bookings%rowtype;
  v_request_id uuid;
begin
  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    return null;
  end if;

  if v_booking.status = 'waitlisted'::public.booking_status then
    insert into public.overbook_requests (
      booking_id,
      slot_id,
      dancer_id,
      status,
      requested_at,
      reviewed_at,
      reviewed_by,
      review_note
    )
    values (
      v_booking.id,
      v_booking.slot_id,
      v_booking.dancer_id,
      'pending'::public.overbook_request_status,
      now(),
      null,
      null,
      null
    )
    on conflict (booking_id)
    do update
      set slot_id = excluded.slot_id,
          dancer_id = excluded.dancer_id,
          status = 'pending'::public.overbook_request_status,
          requested_at = now(),
          reviewed_at = null,
          reviewed_by = null,
          review_note = null
    returning id into v_request_id;

    return v_request_id;
  end if;

  update public.overbook_requests
  set status = case
        when v_booking.status = 'cancelled'::public.booking_status
          then 'cancelled'::public.overbook_request_status
        else 'resolved'::public.overbook_request_status
      end,
      reviewed_at = coalesce(reviewed_at, now())
  where booking_id = v_booking.id
    and status = 'pending'::public.overbook_request_status
  returning id into v_request_id;

  return v_request_id;
end;
$function$
