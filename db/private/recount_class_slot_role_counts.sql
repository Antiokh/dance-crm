-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: recount_class_slot_role_counts
-- Updated:  2026-09-27T01:21:01.667Z

-- overload
-- language: plpgsql
-- args: p_slot_id uuid
-- returns: void

CREATE OR REPLACE FUNCTION private.recount_class_slot_role_counts(p_slot_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_leaders integer := 0;
  v_followers integer := 0;
begin
  if p_slot_id is null then
    return;
  end if;

  select
    count(*) filter (
      where lower(coalesce(r.title_en, '')) = 'leader'
    )::integer,
    count(*) filter (
      where lower(coalesce(r.title_en, '')) = 'follower'
    )::integer
  into v_leaders, v_followers
  from public.bookings b
  left join public.l_dance_role r
    on r.id = b.dance_role_id
  where b.slot_id = p_slot_id
    and b.status = 'booked'::public.booking_status;

  update public.class_slots
  set leader_booked_count = coalesce(v_leaders, 0),
      follower_booked_count = coalesce(v_followers, 0)
  where id = p_slot_id;
end;
$function$
