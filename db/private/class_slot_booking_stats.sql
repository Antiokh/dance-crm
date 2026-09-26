-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: class_slot_booking_stats
-- Updated:  2026-09-26T20:33:34.694Z

-- overload
-- language: sql
-- args: p_slot_id uuid
-- returns: jsonb

CREATE OR REPLACE FUNCTION private.class_slot_booking_stats(p_slot_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'booked_count',
      count(*) filter (where b.status='booked'::public.booking_status),
    'waitlist_count',
      count(*) filter (where b.status='waitlisted'::public.booking_status),
    'leader_count',
      count(*) filter (
        where b.status='booked'::public.booking_status
          and b.dance_role_id = (
            select r.id
            from public.l_dance_role r
            where lower(r.title_en)='leader'
            limit 1
          )
      ),
    'follower_count',
      count(*) filter (
        where b.status='booked'::public.booking_status
          and b.dance_role_id = (
            select r.id
            from public.l_dance_role r
            where lower(r.title_en)='follower'
            limit 1
          )
      )
  )
  from public.bookings b
  where b.slot_id = p_slot_id
$function$
