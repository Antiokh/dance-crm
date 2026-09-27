create table if not exists public.home_attention_items (
  id uuid primary key default extensions.gen_random_uuid(),
  title text not null check (length(btrim(title)) > 0),
  body text,
  event_id uuid references public.dance_events(id) on delete cascade,
  group_id uuid references public.dance_group(id) on delete cascade,
  dancer_id uuid references public.dancer(id) on delete cascade,
  priority smallint not null default 0,
  published boolean not null default false,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid references public.dancer(id) on delete set null
    default private.current_dancer_id(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint home_attention_time_order check (
    ends_at is null or ends_at > starts_at
  ),
  constraint home_attention_single_target check (
    group_id is null or dancer_id is null
  )
);

create index if not exists home_attention_active_idx
  on public.home_attention_items (published, starts_at, ends_at, priority desc);

create index if not exists home_attention_group_idx
  on public.home_attention_items (group_id)
  where group_id is not null;

create index if not exists home_attention_dancer_idx
  on public.home_attention_items (dancer_id)
  where dancer_id is not null;

drop trigger if exists home_attention_touch_updated_at
  on public.home_attention_items;

create trigger home_attention_touch_updated_at
before update on public.home_attention_items
for each row execute function private.touch_updated_at();

alter table public.home_attention_items enable row level security;

grant select, insert, update, delete
  on public.home_attention_items to authenticated;

drop policy if exists home_attention_select on public.home_attention_items;
create policy home_attention_select
on public.home_attention_items
for select
to authenticated
using (
  private.has_app_role('administrator'::public.app_role)
  or (
    published
    and starts_at <= now()
    and (ends_at is null or ends_at > now())
    and (
      (group_id is null and dancer_id is null)
      or dancer_id = private.current_dancer_id()
      or exists (
        select 1
        from public.group_memberships gm
        where gm.group_id = home_attention_items.group_id
          and gm.dancer_id = private.current_dancer_id()
          and gm.status = 'active'::public.group_membership_status
          and (gm.starts_at is null or gm.starts_at <= now())
          and (gm.ends_at is null or gm.ends_at > now())
      )
    )
    and (
      event_id is null
      or exists (
        select 1
        from public.dance_events e
        where e.id = home_attention_items.event_id
          and e.published
          and e.cancelled_at is null
      )
    )
  )
);

drop policy if exists home_attention_admin_insert on public.home_attention_items;
create policy home_attention_admin_insert
on public.home_attention_items
for insert
to authenticated
with check (private.has_app_role('administrator'::public.app_role));

drop policy if exists home_attention_admin_update on public.home_attention_items;
create policy home_attention_admin_update
on public.home_attention_items
for update
to authenticated
using (private.has_app_role('administrator'::public.app_role))
with check (private.has_app_role('administrator'::public.app_role));

drop policy if exists home_attention_admin_delete on public.home_attention_items;
create policy home_attention_admin_delete
on public.home_attention_items
for delete
to authenticated
using (private.has_app_role('administrator'::public.app_role));

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

insert into public.home_attention_items (
  title,
  body,
  event_id,
  priority,
  published,
  starts_at,
  ends_at,
  created_by
)
select
  'Halloween Party',
  '31 октября · специальное событие',
  e.id,
  100,
  true,
  now(),
  e.ends_at,
  e.created_by
from public.dance_events e
where e.title = 'Halloween Party'
  and e.cancelled_at is null
  and not exists (
    select 1
    from public.home_attention_items a
    where a.event_id = e.id
  )
order by e.starts_at
limit 1;
