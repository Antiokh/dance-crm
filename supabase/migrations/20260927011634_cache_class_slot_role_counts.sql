alter table public.class_slots
  add column if not exists leader_booked_count integer not null default 0,
  add column if not exists follower_booked_count integer not null default 0;

alter table public.class_slots
  drop constraint if exists class_slots_leader_booked_count_nonnegative,
  add constraint class_slots_leader_booked_count_nonnegative
    check (leader_booked_count >= 0);

alter table public.class_slots
  drop constraint if exists class_slots_follower_booked_count_nonnegative,
  add constraint class_slots_follower_booked_count_nonnegative
    check (follower_booked_count >= 0);

create or replace function private.recount_class_slot_role_counts(
  p_slot_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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
$function$;

revoke all on function private.recount_class_slot_role_counts(uuid) from public;
revoke all on function private.recount_class_slot_role_counts(uuid) from anon;
revoke all on function private.recount_class_slot_role_counts(uuid) from authenticated;

create or replace function private.refresh_class_slot_role_counts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    perform private.recount_class_slot_role_counts(old.slot_id);
    return old;
  end if;

  perform private.recount_class_slot_role_counts(new.slot_id);

  if tg_op = 'UPDATE'
    and old.slot_id is distinct from new.slot_id
  then
    perform private.recount_class_slot_role_counts(old.slot_id);
  end if;

  return new;
end;
$function$;

revoke all on function private.refresh_class_slot_role_counts() from public;
revoke all on function private.refresh_class_slot_role_counts() from anon;
revoke all on function private.refresh_class_slot_role_counts() from authenticated;

drop trigger if exists bookings_refresh_class_slot_role_counts
  on public.bookings;

create trigger bookings_refresh_class_slot_role_counts
after insert or update or delete on public.bookings
for each row execute function private.refresh_class_slot_role_counts();

update public.class_slots cs
set leader_booked_count = counts.leader_count,
    follower_booked_count = counts.follower_count
from (
  select
    cs2.id as slot_id,
    count(*) filter (
      where b.status = 'booked'::public.booking_status
        and lower(coalesce(r.title_en, '')) = 'leader'
    )::integer as leader_count,
    count(*) filter (
      where b.status = 'booked'::public.booking_status
        and lower(coalesce(r.title_en, '')) = 'follower'
    )::integer as follower_count
  from public.class_slots cs2
  left join public.bookings b
    on b.slot_id = cs2.id
  left join public.l_dance_role r
    on r.id = b.dance_role_id
  group by cs2.id
) counts
where counts.slot_id = cs.id;

create or replace function public.get_my_dancer_home_feed(
  p_event_limit integer default 20,
  p_class_limit integer default 20
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
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
      g.level as group_level,
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
      g.level as group_level,
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
$function$;


drop function if exists private.class_slot_role_balance(uuid);
