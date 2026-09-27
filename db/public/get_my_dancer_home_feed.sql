-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_my_dancer_home_feed
-- Updated:  2026-09-27T00:21:01.471Z

-- overload
-- language: plpgsql
-- args: p_event_limit integer DEFAULT 6, p_class_limit integer DEFAULT 6
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.get_my_dancer_home_feed(p_event_limit integer DEFAULT 6, p_class_limit integer DEFAULT 6)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_events jsonb := '[]'::jsonb;
  v_classes jsonb := '[]'::jsonb;
  v_event_limit integer := least(greatest(coalesce(p_event_limit, 6), 1), 20);
  v_class_limit integer := least(greatest(coalesce(p_class_limit, 6), 1), 20);
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_at), '[]'::jsonb)
  into v_events
  from (
    select
      e.id,
      e.event_type,
      e.title,
      e.description,
      e.starts_at,
      e.ends_at,
      case when v.id is null then null else jsonb_build_object(
        'id', v.id,
        'name', v.name,
        'address', v.address,
        'latitude', v.latitude,
        'longitude', v.longitude
      ) end as venue,
      case when ds.id is null then null else jsonb_build_object(
        'id', ds.id,
        'title_en', ds.title_en,
        'title_ru', ds.title_ru,
        'title_sr', ds.title_sr
      ) end as style
    from public.dance_events e
    left join public.venues v on v.id = e.venue_id
    left join public.l_dance_style ds on ds.id = e.style_id
    where e.published
      and e.cancelled_at is null
      and coalesce(e.ends_at, e.starts_at) >= now()
    order by e.starts_at
    limit v_event_limit
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_at), '[]'::jsonb)
  into v_classes
  from (
    select
      cs.id,
      cs.starts_at,
      cs.ends_at,
      cs.visibility,
      g.id as group_id,
      g.title as group_title,
      g.level as group_level,
      jsonb_build_object(
        'id', ds.id,
        'title_en', ds.title_en,
        'title_ru', ds.title_ru,
        'title_sr', ds.title_sr
      ) as style,
      case when v.id is null then null else jsonb_build_object(
        'id', v.id,
        'name', v.name,
        'address', v.address,
        'latitude', v.latitude,
        'longitude', v.longitude
      ) end as venue,
      (
        select b.status::text
        from public.bookings b
        where b.slot_id = cs.id
          and b.dancer_id = v_dancer_id
          and b.status <> 'cancelled'::public.booking_status
        order by b.booked_at desc
        limit 1
      ) as booking_status
    from public.group_memberships gm
    join public.dance_group g
      on g.id = gm.group_id
     and g.active
    join public.class_slots cs
      on cs.group_id = gm.group_id
     and cs.status = 'scheduled'::public.class_slot_status
     and cs.visibility <> 'hidden'::public.class_visibility
     and cs.starts_at >= now()
    join public.l_dance_style ds
      on ds.id = g.style_id
    left join public.venues v
      on v.id = cs.venue_id
    where gm.dancer_id = v_dancer_id
      and gm.status = 'active'::public.group_membership_status
      and (gm.starts_at is null or gm.starts_at <= now())
      and (gm.ends_at is null or gm.ends_at > now())
    order by cs.starts_at
    limit v_class_limit
  ) x;

  return jsonb_build_object(
    'events', v_events,
    'classes', v_classes
  );
end;
$function$
