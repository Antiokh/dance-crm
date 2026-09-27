
insert into public.styles_levels (
  style_id, code, title_en, title_ru, rank_order
)
select id, 'beginner', 'Beginner', 'Начинающие', 5
from public.l_dance_style
where title_en = 'West-Coast Swing'
on conflict (style_id, code) do update
set title_en = excluded.title_en,
    title_ru = excluded.title_ru,
    rank_order = excluded.rank_order,
    active = true;

alter table public.dance_group
add column level_id bigint;

alter table public.dance_group
add constraint dance_group_level_style_fkey
foreign key (level_id, style_id)
references public.styles_levels(id, style_id)
on delete restrict;

update public.dance_group g
set level_id = l.id
from public.styles_levels l
where l.style_id = g.style_id
  and g.level is not null
  and (
    lower(btrim(l.code)) = lower(btrim(g.level))
    or lower(btrim(l.title_en)) = lower(btrim(g.level))
    or lower(btrim(coalesce(l.title_ru, ''))) = lower(btrim(g.level))
    or lower(btrim(coalesce(l.title_sr, ''))) = lower(btrim(g.level))
  );

do $$
begin
  if exists (
    select 1
    from public.dance_group
    where level is not null
      and btrim(level) <> ''
      and level_id is null
  ) then
    raise exception 'some dance group levels could not be mapped to styles_levels';
  end if;
end
$$;


create or replace view public.v_group_directory
with (security_invoker = true)
as
select
  g.id,
  g.style_id,
  s.title_en as style_title_en,
  s.title_ru as style_title_ru,
  s.title_sr as style_title_sr,
  g.title,
  g.description,
  coalesce(l.title_ru, l.title_en, l.title_sr) as level,
  g.max_capacity,
  g.approval_required,
  g.enrollment_status,
  g.starts_on,
  g.ends_on,
  g.active,
  coalesce(t.trainers, '[]'::jsonb) as trainers,
  m.status as my_membership_status
from public.dance_group g
join public.l_dance_style s on s.id = g.style_id
left join public.styles_levels l
  on l.id = g.level_id
 and l.style_id = g.style_id
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'dancer_id', d.id,
      'name', coalesce(
        nullif(btrim(d.custom_name), ''),
        nullif(btrim(concat_ws(' ', d.first_name, d.last_name)), ''),
        d.telegram_username,
        'Trainer'
      ),
      'username', d.telegram_username,
      'role', gt.trainer_role
    )
    order by
      case gt.trainer_role
        when 'lead'::public.group_trainer_role then 0
        else 1
      end,
      d.id
  ) as trainers
  from public.group_trainers gt
  join public.dancer d on d.id = gt.trainer_id
  where gt.group_id = g.id
    and (gt.starts_on is null or gt.starts_on <= current_date)
    and (gt.ends_on is null or gt.ends_on >= current_date)
) t on true
left join lateral (
  select gm.status
  from public.group_memberships gm
  where gm.group_id = g.id
    and gm.dancer_id = private.current_dancer_id()
  order by gm.requested_at desc
  limit 1
) m on true;


create or replace view public.v_class_slot_directory
with (security_invoker = true)
as
with base as (
  select
    cs.id,
    cs.group_id,
    g.title as group_title,
    coalesce(gl.title_ru, gl.title_en, gl.title_sr) as level,
    g.style_id,
    ds.title_en as style_title_en,
    ds.title_ru as style_title_ru,
    ds.title_sr as style_title_sr,
    ds.is_partner_dance,
    cs.schedule_id,
    cs.occurrence_date,
    cs.starts_at,
    cs.ends_at,
    cs.status,
    cs.source,
    cs.visibility,
    cs.venue_id,
    v.name as venue_name,
    v.address as venue_address,
    v.capacity as venue_capacity,
    cs.capacity_override,
    case
      when v.capacity is null
        then coalesce(cs.capacity_override, g.max_capacity)
      when coalesce(cs.capacity_override, g.max_capacity) is null
        then v.capacity
      else least(coalesce(cs.capacity_override, g.max_capacity), v.capacity)
    end as effective_capacity,
    coalesce(i.instructors, '[]'::jsonb) as instructors,
    gm.status as my_membership_status
  from public.class_slots cs
  join public.dance_group g on g.id = cs.group_id
  join public.l_dance_style ds on ds.id = g.style_id
  left join public.styles_levels gl
    on gl.id = g.level_id
   and gl.style_id = g.style_id
  left join public.venues v on v.id = cs.venue_id
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'dancer_id', d.id,
        'name', coalesce(
          nullif(btrim(d.custom_name), ''),
          nullif(btrim(concat_ws(' ', d.first_name, d.last_name)), ''),
          d.telegram_username,
          'Trainer'
        ),
        'username', d.telegram_username,
        'role', csi.trainer_role
      )
      order by
        case csi.trainer_role
          when 'lead'::public.group_trainer_role then 0
          else 1
        end,
        d.id
    ) as instructors
    from public.class_slot_instructors csi
    join public.dancer d on d.id = csi.trainer_id
    where csi.slot_id = cs.id
  ) i on true
  left join lateral (
    select membership.status
    from public.group_memberships membership
    where membership.group_id = cs.group_id
      and membership.dancer_id = private.current_dancer_id()
    order by membership.requested_at desc
    limit 1
  ) gm on true
)
select
  base.id,
  base.group_id,
  base.group_title,
  base.level,
  base.style_id,
  base.style_title_en,
  base.style_title_ru,
  base.style_title_sr,
  base.is_partner_dance,
  base.schedule_id,
  base.occurrence_date,
  base.starts_at,
  base.ends_at,
  base.status,
  base.source,
  base.visibility,
  base.venue_id,
  base.venue_name,
  base.venue_address,
  base.venue_capacity,
  base.capacity_override,
  base.effective_capacity,
  base.instructors,
  base.my_membership_status,
  coalesce((stats.data ->> 'booked_count')::integer, 0) as booked_count,
  coalesce((stats.data ->> 'waitlist_count')::integer, 0) as waitlist_count,
  coalesce((stats.data ->> 'leader_count')::integer, 0) as leader_count,
  coalesce((stats.data ->> 'follower_count')::integer, 0) as follower_count,
  case
    when base.effective_capacity is null then null::integer
    else greatest(
      base.effective_capacity - coalesce((stats.data ->> 'booked_count')::integer, 0),
      0
    )
  end as spots_left,
  mine.id as my_booking_id,
  mine.status as my_booking_status,
  mine.dance_role_id as my_booking_dance_role_id
from base
left join lateral (
  select private.class_slot_booking_stats(base.id) as data
) stats on true
left join lateral (
  select b.id, b.status, b.dance_role_id
  from public.bookings b
  where b.slot_id = base.id
    and b.dancer_id = private.current_dancer_id()
  limit 1
) mine on true;


create or replace function private.group_generated_title(
  p_group_id uuid,
  p_style_id smallint,
  p_level_id bigint
)
returns text
language sql
stable
security invoker
set search_path = ''
as $function$
  select left(
    concat_ws(
      ' · ',
      coalesce(
        nullif(btrim(s.title_en), ''),
        nullif(btrim(s.title_ru), ''),
        nullif(btrim(s.title_sr), ''),
        'Style'
      ),
      (
        select coalesce(
          nullif(btrim(l.title_en), ''),
          nullif(btrim(l.title_ru), ''),
          nullif(btrim(l.title_sr), '')
        )
        from public.styles_levels l
        where l.id = p_level_id
          and l.style_id = p_style_id
      ),
      (
        select coalesce(
          nullif(btrim(d.custom_name), ''),
          nullif(btrim(concat_ws(' ', d.first_name, d.last_name)), ''),
          case
            when nullif(btrim(d.telegram_username), '') is not null
              then '@' || btrim(d.telegram_username)
            else null
          end
        )
        from public.group_trainers gt
        join public.dancer d on d.id = gt.trainer_id
        where gt.group_id = p_group_id
          and gt.trainer_role = 'lead'::public.group_trainer_role
        order by
          (
            (gt.starts_on is null or gt.starts_on <= current_date)
            and (gt.ends_on is null or gt.ends_on >= current_date)
          ) desc,
          gt.starts_on desc nulls last,
          gt.created_at desc,
          gt.trainer_id
        limit 1
      )
    ),
    160
  )
  from public.l_dance_style s
  where s.id = p_style_id
$function$;

revoke all on function private.group_generated_title(uuid, smallint, bigint)
from public, anon, authenticated;

create or replace function private.set_generated_group_title()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  new.title := private.group_generated_title(
    new.id,
    new.style_id,
    new.level_id
  );
  return new;
end;
$function$;

revoke all on function private.set_generated_group_title()
from public, anon, authenticated;

create trigger dance_group_generate_title
before insert or update
on public.dance_group
for each row
execute function private.set_generated_group_title();

create or replace function private.refresh_group_title(
  p_group_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $function$
  update public.dance_group g
  set title = private.group_generated_title(
    g.id,
    g.style_id,
    g.level_id
  )
  where g.id = p_group_id
$function$;

revoke all on function private.refresh_group_title(uuid)
from public, anon, authenticated;

create or replace function private.refresh_group_title_from_trainers()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op <> 'INSERT' then
    perform private.refresh_group_title(old.group_id);
  end if;

  if tg_op <> 'DELETE' then
    perform private.refresh_group_title(new.group_id);
  end if;

  return null;
end;
$function$;

revoke all on function private.refresh_group_title_from_trainers()
from public, anon, authenticated;

create trigger group_trainers_refresh_group_title
after insert or update or delete
on public.group_trainers
for each row
execute function private.refresh_group_title_from_trainers();

create or replace function private.refresh_group_titles_from_dancer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_group_id uuid;
begin
  if new.custom_name is not distinct from old.custom_name
    and new.first_name is not distinct from old.first_name
    and new.last_name is not distinct from old.last_name
    and new.telegram_username is not distinct from old.telegram_username
  then
    return null;
  end if;

  for v_group_id in
    select gt.group_id
    from public.group_trainers gt
    where gt.trainer_id = new.id
      and gt.trainer_role = 'lead'::public.group_trainer_role
  loop
    perform private.refresh_group_title(v_group_id);
  end loop;

  return null;
end;
$function$;

revoke all on function private.refresh_group_titles_from_dancer()
from public, anon, authenticated;

create trigger dancer_refresh_group_titles
after update of custom_name, first_name, last_name, telegram_username
on public.dancer
for each row
execute function private.refresh_group_titles_from_dancer();

create or replace function private.refresh_group_titles_from_style()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_group_id uuid;
begin
  if new.title_en is not distinct from old.title_en
    and new.title_ru is not distinct from old.title_ru
    and new.title_sr is not distinct from old.title_sr
  then
    return null;
  end if;

  for v_group_id in
    select g.id
    from public.dance_group g
    where g.style_id = new.id
  loop
    perform private.refresh_group_title(v_group_id);
  end loop;

  return null;
end;
$function$;

revoke all on function private.refresh_group_titles_from_style()
from public, anon, authenticated;

create trigger dance_style_refresh_group_titles
after update of title_en, title_ru, title_sr
on public.l_dance_style
for each row
execute function private.refresh_group_titles_from_style();

create or replace function private.refresh_group_titles_from_level()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_group_id uuid;
begin
  if new.title_en is not distinct from old.title_en
    and new.title_ru is not distinct from old.title_ru
    and new.title_sr is not distinct from old.title_sr
  then
    return null;
  end if;

  for v_group_id in
    select g.id
    from public.dance_group g
    where g.level_id = new.id
      and g.style_id = new.style_id
  loop
    perform private.refresh_group_title(v_group_id);
  end loop;

  return null;
end;
$function$;

revoke all on function private.refresh_group_titles_from_level()
from public, anon, authenticated;

create trigger styles_levels_refresh_group_titles
after update of title_en, title_ru, title_sr
on public.styles_levels
for each row
execute function private.refresh_group_titles_from_level();

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
      coalesce(gl.title_ru, gl.title_en, gl.title_sr) as group_level,
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
      coalesce(gl.title_ru, gl.title_en, gl.title_sr) as group_level,
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

grant select (level_id)
on public.dance_group
to anon;

alter table public.dance_group
drop column level;

update public.dance_group
set title = title;
