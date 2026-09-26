-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: cancel_bookings_for_cancelled_slot
-- Updated:  2026-09-26T20:33:45.517Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION private.cancel_bookings_for_cancelled_slot()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.status is distinct from new.status
    and new.status = 'cancelled'::public.class_slot_status
  then
    update public.bookings
    set status = 'cancelled'::public.booking_status,
        cancelled_at = coalesce(new.cancelled_at, now()),
        cancellation_type = 'slot_cancelled'::public.booking_cancellation_type
    where slot_id = new.id
      and status in (
        'booked'::public.booking_status,
        'waitlisted'::public.booking_status
      );
  end if;

  return new;
end;
$function$
