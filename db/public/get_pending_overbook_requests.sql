-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_pending_overbook_requests
-- Updated:  2026-09-27T01:12:02.363Z

-- overload
-- language: sql
-- args: 
-- returns: TABLE(request_id uuid, booking_id uuid, slot_id uuid, dancer_id uuid, dancer_name text, group_id uuid, group_title text, starts_at timestamp with time zone, requested_at timestamp with time zone)

CREATE OR REPLACE FUNCTION public.get_pending_overbook_requests()
 RETURNS TABLE(request_id uuid, booking_id uuid, slot_id uuid, dancer_id uuid, dancer_name text, group_id uuid, group_title text, starts_at timestamp with time zone, requested_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    r.id,
    r.booking_id,
    r.slot_id,
    r.dancer_id,
    coalesce(
      nullif(d.custom_name, ''),
      nullif(concat_ws(' ', d.first_name, d.last_name), ''),
      d.telegram_username,
      'Dancer'
    ) as dancer_name,
    cs.group_id,
    g.title,
    cs.starts_at,
    r.requested_at
  from public.overbook_requests r
  join public.bookings b on b.id = r.booking_id
  join public.class_slots cs on cs.id = r.slot_id
  join public.dance_group g on g.id = cs.group_id
  join public.dancer d on d.id = r.dancer_id
  where r.status = 'pending'::public.overbook_request_status
    and b.status = 'waitlisted'::public.booking_status
    and private.can_operate_slot(r.slot_id)
  order by r.requested_at, r.id
$function$
