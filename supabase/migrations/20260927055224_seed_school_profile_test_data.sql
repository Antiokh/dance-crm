
do $$
declare
  v_dancer_id uuid;
  v_auth_user_id uuid;
  v_wcs_group_id uuid;
  v_hustle_group_id uuid;
  v_wcs_style_id smallint;
  v_center_venue_id uuid;
  v_vracar_venue_id uuid;
  v_plan_id uuid;
  v_subscription_id uuid;
  v_past_slot_id uuid;
  v_past_booking_id uuid;
begin
  select d.id, d.auth_user_id
  into v_dancer_id, v_auth_user_id
  from public.dancer d
  where d.telegram_username = 'antiokh'
  limit 1;

  if v_dancer_id is null or v_auth_user_id is null then
    raise exception 'demo dancer antiokh not found';
  end if;

  perform set_config('request.jwt.claim.sub', v_auth_user_id::text, true);

  select id, style_id
  into v_wcs_group_id, v_wcs_style_id
  from public.dance_group
  where title = 'WCS Beginner'
  order by created_at
  limit 1;

  select id
  into v_hustle_group_id
  from public.dance_group
  where title = 'Hustle'
  order by created_at
  limit 1;

  if v_wcs_group_id is null or v_hustle_group_id is null then
    raise exception 'demo groups are missing';
  end if;

  select id
  into v_center_venue_id
  from public.venues
  where name = 'Тестовый зал · Центр'
  order by created_at
  limit 1;

  if v_center_venue_id is null then
    insert into public.venues (
      name,
      address,
      capacity,
      notes,
      active
    )
    values (
      'Тестовый зал · Центр',
      'Белград · тестовый адрес',
      28,
      'demo_seed: school_profile_test_v1',
      true
    )
    returning id into v_center_venue_id;
  end if;

  select id
  into v_vracar_venue_id
  from public.venues
  where name = 'Тестовый зал · Врачар'
  order by created_at
  limit 1;

  if v_vracar_venue_id is null then
    insert into public.venues (
      name,
      address,
      capacity,
      notes,
      active
    )
    values (
      'Тестовый зал · Врачар',
      'Белград · тестовый адрес',
      20,
      'demo_seed: school_profile_test_v1',
      true
    )
    returning id into v_vracar_venue_id;
  end if;

  insert into public.group_trainers (
    group_id,
    trainer_id,
    trainer_role,
    starts_on
  )
  values
    (
      v_wcs_group_id,
      v_dancer_id,
      'lead'::public.group_trainer_role,
      current_date - 30
    ),
    (
      v_hustle_group_id,
      v_dancer_id,
      'lead'::public.group_trainer_role,
      current_date - 30
    )
  on conflict (group_id, trainer_id)
  do update
    set trainer_role = excluded.trainer_role,
        starts_on = coalesce(public.group_trainers.starts_on, excluded.starts_on),
        ends_on = null;

  update public.class_schedules
  set venue_id = case
        when group_id = v_wcs_group_id then v_center_venue_id
        when group_id = v_hustle_group_id then v_vracar_venue_id
        else venue_id
      end
  where group_id in (v_wcs_group_id, v_hustle_group_id);

  update public.class_slots
  set venue_id = case
        when group_id = v_wcs_group_id then v_center_venue_id
        when group_id = v_hustle_group_id then v_vracar_venue_id
        else venue_id
      end
  where group_id in (v_wcs_group_id, v_hustle_group_id)
    and starts_at > now();

  select id
  into v_plan_id
  from public.subscription_plans
  where name = 'Тестовый · 8 занятий'
  order by created_at
  limit 1;

  if v_plan_id is null then
    v_plan_id := public.admin_create_subscription_plan(
      'Тестовый · 8 занятий',
      'Тестовый абонемент для проверки профиля',
      'one_time'::public.subscription_renewal_mode,
      'credits'::public.subscription_usage_mode,
      8,
      30,
      2,
      7,
      '{}'::smallint[],
      array[v_wcs_group_id, v_hustle_group_id]::uuid[]
    );
  end if;

  select s.id
  into v_subscription_id
  from public.student_subscriptions s
  where s.dancer_id = v_dancer_id
    and s.plan_id = v_plan_id
    and s.status = 'active'::public.student_subscription_status
    and s.metadata->>'demo_seed' = 'school_profile_test_v1'
  order by s.created_at desc
  limit 1;

  if v_subscription_id is null then
    v_subscription_id := public.admin_issue_subscription(
      v_dancer_id,
      v_plan_id,
      now() - interval '5 days',
      null::integer,
      null::integer,
      30,
      null::smallint[],
      null::uuid[]
    );

    update public.student_subscriptions
    set metadata = metadata || jsonb_build_object(
      'demo_seed',
      'school_profile_test_v1'
    )
    where id = v_subscription_id;
  end if;

  select cs.id
  into v_past_slot_id
  from public.class_slots cs
  where cs.group_id = v_wcs_group_id
    and cs.source = 'manual'::public.class_slot_source
    and cs.status = 'completed'::public.class_slot_status
    and cs.cancellation_reason = 'demo_seed: school_profile_test_v1'
  order by cs.starts_at desc
  limit 1;

  if v_past_slot_id is null then
    insert into public.class_slots (
      group_id,
      starts_at,
      ends_at,
      venue_id,
      visibility,
      status,
      source,
      cancellation_reason
    )
    values (
      v_wcs_group_id,
      ((current_date - 7) + time '19:00') at time zone 'Europe/Belgrade',
      ((current_date - 7) + time '20:00') at time zone 'Europe/Belgrade',
      v_center_venue_id,
      'members'::public.class_visibility,
      'completed'::public.class_slot_status,
      'manual'::public.class_slot_source,
      'demo_seed: school_profile_test_v1'
    )
    returning id into v_past_slot_id;
  end if;

  select b.id
  into v_past_booking_id
  from public.bookings b
  where b.slot_id = v_past_slot_id
    and b.dancer_id = v_dancer_id
  limit 1;

  if v_past_booking_id is null then
    insert into public.bookings (
      slot_id,
      dancer_id,
      status,
      attendance_status,
      dance_role_id,
      booked_at
    )
    values (
      v_past_slot_id,
      v_dancer_id,
      'booked'::public.booking_status,
      'attended'::public.attendance_status,
      1,
      ((current_date - 8) + time '12:00') at time zone 'Europe/Belgrade'
    )
    returning id into v_past_booking_id;
  else
    update public.bookings
    set status = 'booked'::public.booking_status,
        attendance_status = 'attended'::public.attendance_status,
        dance_role_id = 1,
        cancelled_at = null,
        cancellation_type = null
    where id = v_past_booking_id;
  end if;
end
$$;
