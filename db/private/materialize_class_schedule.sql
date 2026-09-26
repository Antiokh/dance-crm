-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: materialize_class_schedule
-- Updated:  2026-09-26T20:34:19.589Z

-- overload
-- language: plpgsql
-- args: p_schedule_id uuid, p_through_date date
-- returns: integer

CREATE OR REPLACE FUNCTION private.materialize_class_schedule(p_schedule_id uuid, p_through_date date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_schedule public.class_schedules%rowtype;
  v_from date;
  v_through date;
  v_date date;
  v_slot_id uuid;
  v_inserted integer := 0;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  select *
  into v_schedule
  from public.class_schedules
  where id = p_schedule_id;

  if not found then
    raise exception 'class schedule not found'
      using errcode='P0002';
  end if;

  if not v_schedule.active then
    return 0;
  end if;

  v_from := greatest(v_schedule.valid_from, current_date);
  v_through := least(
    coalesce(v_schedule.valid_until, p_through_date),
    p_through_date
  );

  if v_through < v_from then
    return 0;
  end if;

  for v_date in
    select gs::date
    from generate_series(
      v_from::timestamp,
      v_through::timestamp,
      interval '1 day'
    ) gs
    where extract(dow from gs)::smallint = v_schedule.weekday
    order by gs
  loop
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
      (v_date + v_schedule.start_time) at time zone v_schedule.timezone,
      (v_date + v_schedule.end_time) at time zone v_schedule.timezone,
      v_schedule.venue_id,
      v_schedule.capacity_override,
      v_schedule.visibility,
      'scheduled'::public.class_slot_status,
      'schedule'::public.class_slot_source
    )
    on conflict (schedule_id, occurrence_date)
    where schedule_id is not null and occurrence_date is not null
    do nothing
    returning id into v_slot_id;

    if v_slot_id is not null then
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

      v_inserted := v_inserted + 1;
      v_slot_id := null;
    end if;
  end loop;

  return v_inserted;
end;
$function$
