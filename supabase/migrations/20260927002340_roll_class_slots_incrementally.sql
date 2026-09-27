create or replace function private.ensure_next_class_slot(
  p_schedule_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_schedule public.class_schedules%rowtype;
  v_date date;
  v_slot_id uuid;
begin
  select *
  into v_schedule
  from public.class_schedules
  where id = p_schedule_id
  for update;

  if not found or not v_schedule.active then
    return false;
  end if;

  if exists (
    select 1
    from public.class_slots cs
    where cs.schedule_id = p_schedule_id
      and cs.status = 'scheduled'::public.class_slot_status
      and cs.ends_at > now()
  ) then
    return false;
  end if;

  select gs::date
  into v_date
  from generate_series(
    greatest(v_schedule.valid_from, current_date)::timestamp,
    (greatest(v_schedule.valid_from, current_date) + 21)::timestamp,
    interval '1 day'
  ) gs
  where extract(dow from gs)::smallint = v_schedule.weekday
    and (v_schedule.valid_until is null or gs::date <= v_schedule.valid_until)
    and ((gs::date + v_schedule.start_time) at time zone v_schedule.timezone) > now()
    and not exists (
      select 1
      from public.class_slots existing
      where existing.schedule_id = p_schedule_id
        and existing.occurrence_date = gs::date
    )
  order by gs
  limit 1;

  if v_date is null then
    return false;
  end if;

  insert into public.class_slots (
    group_id, schedule_id, occurrence_date, starts_at, ends_at,
    venue_id, capacity_override, visibility, status, source
  )
  values (
    v_schedule.group_id,
    v_schedule.id,
    v_date,
    (v_date + v_schedule.start_time) at time zone v_schedule.timezone,
    (v_date + v_schedule.end_time) at time zone v_schedule.timezone,
    v_schedule.venue_id,
    v_schedule.capacity_override,
    v_schedule.visibility,
    'scheduled'::public.class_slot_status,
    'schedule'::public.class_slot_source
  )
  returning id into v_slot_id;

  insert into public.class_slot_instructors (
    slot_id, trainer_id, trainer_role
  )
  select v_slot_id, csi.trainer_id, csi.trainer_role
  from public.class_schedule_instructors csi
  where csi.schedule_id = v_schedule.id
  on conflict do nothing;

  return true;
end;
$function$;

revoke all on function private.ensure_next_class_slot(uuid) from public;
revoke all on function private.ensure_next_class_slot(uuid) from anon;
revoke all on function private.ensure_next_class_slot(uuid) from authenticated;

create or replace function private.roll_class_slots()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_schedule record;
  v_completed integer := 0;
  v_created integer := 0;
begin
  update public.class_slots
  set status = 'completed'::public.class_slot_status
  where status = 'scheduled'::public.class_slot_status
    and ends_at <= now();

  get diagnostics v_completed = row_count;

  for v_schedule in
    select id
    from public.class_schedules
    where active
      and valid_from <= current_date
      and (valid_until is null or valid_until >= current_date)
    order by id
  loop
    if private.ensure_next_class_slot(v_schedule.id) then
      v_created := v_created + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'completed', v_completed,
    'created', v_created
  );
end;
$function$;

revoke all on function private.roll_class_slots() from public;
revoke all on function private.roll_class_slots() from anon;
revoke all on function private.roll_class_slots() from authenticated;

create or replace function private.materialize_class_schedule(
  p_schedule_id uuid,
  p_through_date date
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  if private.ensure_next_class_slot(p_schedule_id) then
    return 1;
  end if;

  return 0;
end;
$function$;

create or replace function public.admin_create_class_schedule(
  p_group_id uuid,
  p_venue_id uuid,
  p_weekday smallint,
  p_start_time time without time zone,
  p_end_time time without time zone,
  p_timezone text default 'Europe/Belgrade'::text,
  p_valid_from date default current_date,
  p_valid_until date default null::date,
  p_capacity_override integer default null::integer,
  p_visibility public.class_visibility default 'public'::public.class_visibility,
  p_trainer_ids uuid[] default '{}'::uuid[]
)
returns uuid
language plpgsql
set search_path = ''
as $function$
declare
  v_schedule_id uuid;
  v_trainer_id uuid;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  insert into public.class_schedules (
    group_id, venue_id, weekday, start_time, end_time, timezone,
    valid_from, valid_until, capacity_override, visibility
  )
  values (
    p_group_id, p_venue_id, p_weekday, p_start_time, p_end_time, p_timezone,
    p_valid_from, p_valid_until, p_capacity_override, p_visibility
  )
  returning id into v_schedule_id;

  foreach v_trainer_id in array coalesce(p_trainer_ids, '{}'::uuid[])
  loop
    insert into public.class_schedule_instructors (
      schedule_id, trainer_id, trainer_role
    )
    values (
      v_schedule_id, v_trainer_id, 'lead'::public.group_trainer_role
    )
    on conflict do nothing;
  end loop;

  perform private.ensure_next_class_slot(v_schedule_id);

  return v_schedule_id;
end;
$function$;

with ranked as (
  select
    cs.id,
    row_number() over (
      partition by cs.schedule_id
      order by cs.starts_at, cs.id
    ) as rn
  from public.class_slots cs
  where cs.schedule_id is not null
    and cs.source = 'schedule'::public.class_slot_source
    and cs.status = 'scheduled'::public.class_slot_status
    and cs.ends_at > now()
),
deletable as (
  select r.id
  from ranked r
  where r.rn > 1
    and not exists (
      select 1
      from public.bookings b
      where b.slot_id = r.id
        and b.status <> 'cancelled'::public.booking_status
    )
)
delete from public.class_slots cs
using deletable d
where cs.id = d.id;

select private.roll_class_slots();

select cron.schedule(
  'class-slot-rollover',
  '*/5 * * * *',
  'select private.roll_class_slots();'
);
