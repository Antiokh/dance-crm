
create or replace function private.dancer_styles_context(
  p_dancer_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $function$
  with profiles as (
    select
      p.id,
      p.dancer_id,
      p.style_id,
      p.is_leader,
      p.is_trainer,
      p.is_default,
      p.training_level_id,
      p.created_at,
      case when p.is_leader then 1::smallint else 2::smallint end as role_id,
      tl.code as training_code,
      tl.title_en as training_title_en,
      tl.title_ru as training_title_ru,
      tl.title_sr as training_title_sr,
      tl.rank_order as training_rank_order,
      (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'id', cp.id,
              'system_code', cp.system_code,
              'level_id', cp.level_id,
              'points', cp.points,
              'external_profile_id', cp.external_profile_id,
              'last_synced_at', cp.last_synced_at,
              'level', jsonb_build_object(
                'code', cl.code,
                'title_en', cl.title_en,
                'title_ru', cl.title_ru,
                'title_sr', cl.title_sr,
                'rank_order', cl.rank_order,
                'is_sport_achievement', cl.is_sport_achievement
              )
            )
            order by cp.system_code
          ),
          '[]'::jsonb
        )
        from public.dancer_style_competition_profile cp
        join public.styles_levels cl on cl.id=cp.level_id
        where cp.style_profile_id=p.id
      ) as competition_profiles
    from public.dancer_style_profile p
    left join public.styles_levels tl
      on tl.id=p.training_level_id
     and tl.style_id=p.style_id
    where p.dancer_id=p_dancer_id
  ),
  grouped as (
    select
      s.id,
      s.title_en,
      s.title_ru,
      s.title_sr,
      s.is_partner_dance,
      coalesce(
        max(p.role_id) filter(where p.is_default),
        min(p.role_id)
      ) as main_role,
      bool_or(p.is_trainer) as is_trainer,
      jsonb_agg(distinct p.role_id order by p.role_id) as role_ids,
      jsonb_agg(
        jsonb_build_object(
          'id',p.id,
          'is_leader',p.is_leader,
          'is_trainer',p.is_trainer,
          'is_default',p.is_default,
          'training_level_id',p.training_level_id,
          'training_level',
            case when p.training_level_id is null then null
            else jsonb_build_object(
              'code',p.training_code,
              'title_en',p.training_title_en,
              'title_ru',p.training_title_ru,
              'title_sr',p.training_title_sr,
              'rank_order',p.training_rank_order
            ) end,
          'competition_profiles',p.competition_profiles
        )
        order by p.is_default desc,p.is_leader desc,p.created_at
      ) as profiles
    from profiles p
    join public.l_dance_style s on s.id=p.style_id
    group by s.id,s.title_en,s.title_ru,s.title_sr,s.is_partner_dance
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',g.id,
        'title_en',g.title_en,
        'title_ru',g.title_ru,
        'title_sr',g.title_sr,
        'is_partner_dance',g.is_partner_dance,
        'main_role',g.main_role,
        'role_ids',g.role_ids,
        'is_trainer',g.is_trainer,
        'profiles',g.profiles
      )
      order by g.id
    ),
    '[]'::jsonb
  )
  from grouped g
$function$;

revoke all on function private.dancer_styles_context(uuid)
from public,anon,authenticated;
grant execute on function private.dancer_styles_context(uuid)
to authenticated;

CREATE OR REPLACE FUNCTION public.get_my_dancer_home_feed(p_event_limit integer DEFAULT 20, p_class_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_today date := (now() at time zone 'Europe/Belgrade')::date;
  v_attention jsonb := '[]'::jsonb;
  v_today_events jsonb := '[]'::jsonb;
  v_today_classes jsonb := '[]'::jsonb;
  v_events jsonb := '[]'::jsonb;
  v_classes jsonb := '[]'::jsonb;
  v_event_limit integer := least(greatest(coalesce(p_event_limit, 20), 1), 50);
  v_class_limit integer := least(greatest(coalesce(p_class_limit, 20), 1), 50);
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.priority desc, x.created_at desc),
    '[]'::jsonb
  )
  into v_attention
  from (
    select
      a.id,
      a.title,
      a.body,
      a.priority,
      a.created_at,
      case when e.id is null then null else jsonb_build_object(
        'id', e.id,
        'event_type', e.event_type,
        'title', e.title,
        'description', e.description,
        'starts_at', e.starts_at,
        'ends_at', e.ends_at,
        'venue', case when v.id is null then null else jsonb_build_object(
          'id', v.id,
          'name', v.name,
          'address', v.address,
          'latitude', v.latitude,
          'longitude', v.longitude
        ) end,
        'style', case when ds.id is null then null else jsonb_build_object(
          'id', ds.id,
          'title_en', ds.title_en,
          'title_ru', ds.title_ru,
          'title_sr', ds.title_sr
        ) end
      ) end as event
    from public.home_attention_items a
    left join public.dance_events e on e.id = a.event_id
    left join public.venues v on v.id = e.venue_id
    left join public.l_dance_style ds on ds.id = e.style_id
    where a.published
      and a.starts_at <= now()
      and (a.ends_at is null or a.ends_at > now())
      and (
        (a.group_id is null and a.dancer_id is null)
        or a.dancer_id = v_dancer_id
        or exists (
          select 1
          from public.group_memberships gm
          where gm.group_id = a.group_id
            and gm.dancer_id = v_dancer_id
            and gm.status = 'active'::public.group_membership_status
            and (gm.starts_at is null or gm.starts_at <= now())
            and (gm.ends_at is null or gm.ends_at > now())
        )
      )
      and (
        a.event_id is null
        or (
          e.published
          and e.cancelled_at is null
        )
      )
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_at), '[]'::jsonb)
  into v_today_events
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
      and (e.starts_at at time zone 'Europe/Belgrade')::date = v_today
    order by e.starts_at
  ) x;

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
      and (e.starts_at at time zone 'Europe/Belgrade')::date > v_today
    order by e.starts_at
    limit v_event_limit
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_at), '[]'::jsonb)
  into v_today_classes
  from (
    select
      cs.id,
      cs.starts_at,
      cs.ends_at,
      cs.visibility,
      g.id as group_id,
      g.title as group_title,
      coalesce(gl.title_en, gl.title_ru, gl.title_sr) as group_level,
      jsonb_build_object(
        'id', ds.id,
        'title_en', ds.title_en,
        'title_ru', ds.title_ru,
        'title_sr', ds.title_sr,
        'is_partner_dance', ds.is_partner_dance
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
      ) as booking_status,
      case
        when ds.is_partner_dance
          then jsonb_build_object(
            'leader', cs.leader_booked_count,
            'follower', cs.follower_booked_count
          )
        else null
      end as role_balance
    from public.group_memberships gm
    join public.dance_group g
      on g.id = gm.group_id
     and g.active
    join public.class_slots cs
      on cs.group_id = gm.group_id
     and cs.status = 'scheduled'::public.class_slot_status
     and cs.visibility <> 'hidden'::public.class_visibility
     and cs.ends_at > now()
    join public.l_dance_style ds on ds.id = g.style_id
    left join public.styles_levels gl
      on gl.id = g.level_id
     and gl.style_id = g.style_id
    left join public.venues v on v.id = cs.venue_id
    where gm.dancer_id = v_dancer_id
      and gm.status = 'active'::public.group_membership_status
      and (gm.starts_at is null or gm.starts_at <= now())
      and (gm.ends_at is null or gm.ends_at > now())
      and (cs.starts_at at time zone 'Europe/Belgrade')::date = v_today
    order by cs.starts_at
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
      coalesce(gl.title_en, gl.title_ru, gl.title_sr) as group_level,
      jsonb_build_object(
        'id', ds.id,
        'title_en', ds.title_en,
        'title_ru', ds.title_ru,
        'title_sr', ds.title_sr,
        'is_partner_dance', ds.is_partner_dance
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
      ) as booking_status,
      case
        when ds.is_partner_dance
          then jsonb_build_object(
            'leader', cs.leader_booked_count,
            'follower', cs.follower_booked_count
          )
        else null
      end as role_balance
    from public.group_memberships gm
    join public.dance_group g
      on g.id = gm.group_id
     and g.active
    join public.class_slots cs
      on cs.group_id = gm.group_id
     and cs.status = 'scheduled'::public.class_slot_status
     and cs.visibility <> 'hidden'::public.class_visibility
     and cs.ends_at > now()
    join public.l_dance_style ds on ds.id = g.style_id
    left join public.styles_levels gl
      on gl.id = g.level_id
     and gl.style_id = g.style_id
    left join public.venues v on v.id = cs.venue_id
    where gm.dancer_id = v_dancer_id
      and gm.status = 'active'::public.group_membership_status
      and (gm.starts_at is null or gm.starts_at <= now())
      and (gm.ends_at is null or gm.ends_at > now())
      and (cs.starts_at at time zone 'Europe/Belgrade')::date > v_today
    order by cs.starts_at
    limit v_class_limit
  ) x;

  return jsonb_build_object(
    'attention', v_attention,
    'today_events', v_today_events,
    'today_classes', v_today_classes,
    'events', v_events,
    'classes', v_classes
  );
end;
$function$
;
