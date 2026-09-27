-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: ensure_next_class_slot
-- Updated:  2026-09-27T00:31:01.434Z

-- overload
-- language: plpgsql
-- args: p_schedule_id uuid
-- returns: boolean

CREATE OR REPLACE FUNCTION private.ensure_next_class_slot(p_schedule_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    (
      greatest(v_schedule.valid_from, current_date)
      + 21
    )::timestamp,
    interval '1 day'
  ) gs
  where extract(dow from gs)::smallint = v_schedule.weekday
    and (
      v_schedule.valid_until is null
      or gs::date <= v_schedule.valid_until
    )
    and (
      (gs::date + v_schedule.start_time)
        at time zone v_schedule.timezone
    ) > now()
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
    group_id,
    schedule_id,
    occurrence_date,
    starts_at,
    ends_at,
    venue_id,
    capacity_override,
    visibility,
    status,
    source
  )
  values (
    v_schedule.group_id,
    v_schedule.id,
    v_date,
    (v_date + v_schedule.start_time)
      at time zone v_schedule.timezone,
    (v_date + v_schedule.end_time)
      at time zone v_schedule.timezone,
    v_schedule.venue_id,
    v_schedule.capacity_override,
    v_schedule.visibility,
    'scheduled'::public.class_slot_status,
    'schedule'::public.class_slot_source
  )
  returning id into v_slot_id;

  insert into public.class_slot_instructors (
    slot_id,
    trainer_id,
    trainer_role
  )
  select
    v_slot_id,
    csi.trainer_id,
    csi.trainer_role
  from public.class_schedule_instructors csi
  where csi.schedule_id = v_schedule.id
  on conflict do nothing;

  return true;
end;
$function$
