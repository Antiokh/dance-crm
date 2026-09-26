-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_create_class_schedule
-- Updated:  2026-09-26T20:35:28.150Z

-- overload
-- language: plpgsql
-- args: p_group_id uuid, p_venue_id uuid, p_weekday smallint, p_start_time time without time zone, p_end_time time without time zone, p_timezone text DEFAULT 'Europe/Belgrade'::text, p_valid_from date DEFAULT CURRENT_DATE, p_valid_until date DEFAULT NULL::date, p_capacity_override integer DEFAULT NULL::integer, p_visibility class_visibility DEFAULT 'public'::class_visibility, p_trainer_ids uuid[] DEFAULT '{}'::uuid[]
-- returns: uuid

CREATE OR REPLACE FUNCTION public.admin_create_class_schedule(p_group_id uuid, p_venue_id uuid, p_weekday smallint, p_start_time time without time zone, p_end_time time without time zone, p_timezone text DEFAULT 'Europe/Belgrade'::text, p_valid_from date DEFAULT CURRENT_DATE, p_valid_until date DEFAULT NULL::date, p_capacity_override integer DEFAULT NULL::integer, p_visibility class_visibility DEFAULT 'public'::class_visibility, p_trainer_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_schedule_id uuid;
  v_trainer_id uuid;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  insert into public.class_schedules (
    group_id,
    venue_id,
    weekday,
    start_time,
    end_time,
    timezone,
    valid_from,
    valid_until,
    capacity_override,
    visibility
  )
  values (
    p_group_id,
    p_venue_id,
    p_weekday,
    p_start_time,
    p_end_time,
    p_timezone,
    p_valid_from,
    p_valid_until,
    p_capacity_override,
    p_visibility
  )
  returning id into v_schedule_id;

  foreach v_trainer_id in array coalesce(p_trainer_ids, '{}'::uuid[])
  loop
    insert into public.class_schedule_instructors (
      schedule_id,
      trainer_id,
      trainer_role
    )
    values (
      v_schedule_id,
      v_trainer_id,
      'lead'::public.group_trainer_role
    )
    on conflict do nothing;
  end loop;

  perform private.materialize_class_schedule(
    v_schedule_id,
    least(
      coalesce(p_valid_until, current_date + 56),
      current_date + 56
    )
  );

  return v_schedule_id;
end;
$function$
