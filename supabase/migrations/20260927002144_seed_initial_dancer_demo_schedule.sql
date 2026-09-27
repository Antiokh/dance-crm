do $$
declare
  v_auth_user_id uuid;
  v_dancer_id uuid;
  v_wcs_style_id smallint;
  v_hustle_style_id smallint;
  v_wcs_group_id uuid;
  v_hustle_group_id uuid;
begin
  select d.auth_user_id, d.id
  into v_auth_user_id, v_dancer_id
  from public.dancer d
  join public.dancer_app_roles r on r.dancer_id = d.id
  where r.role = 'administrator'::public.app_role
    and d.auth_user_id is not null
  order by d.created_at, d.id
  limit 1;

  if v_auth_user_id is null or v_dancer_id is null then
    raise exception 'administrator dancer is required for demo seed';
  end if;

  perform set_config('request.jwt.claim.sub', v_auth_user_id::text, true);

  select id into v_wcs_style_id
  from public.l_dance_style
  where lower(title_en) = 'west-coast swing'
  limit 1;

  select id into v_hustle_style_id
  from public.l_dance_style
  where lower(title_en) = 'hustle'
  limit 1;

  if v_wcs_style_id is null or v_hustle_style_id is null then
    raise exception 'required dance styles are missing';
  end if;

  select id into v_wcs_group_id
  from public.dance_group
  where title = 'WCS Beginner'
  order by created_at
  limit 1;

  if v_wcs_group_id is null then
    insert into public.dance_group (
      style_id, title, level, approval_required, enrollment_status, active
    )
    values (
      v_wcs_style_id, 'WCS Beginner', 'Beginner', false,
      'open'::public.group_enrollment_status, true
    )
    returning id into v_wcs_group_id;
  end if;

  select id into v_hustle_group_id
  from public.dance_group
  where title = 'Hustle'
  order by created_at
  limit 1;

  if v_hustle_group_id is null then
    insert into public.dance_group (
      style_id, title, level, approval_required, enrollment_status, active
    )
    values (
      v_hustle_style_id, 'Hustle', null, false,
      'open'::public.group_enrollment_status, true
    )
    returning id into v_hustle_group_id;
  end if;

  if not exists (
    select 1
    from public.group_memberships gm
    where gm.group_id = v_wcs_group_id
      and gm.dancer_id = v_dancer_id
      and gm.status in (
        'pending'::public.group_membership_status,
        'active'::public.group_membership_status
      )
  ) then
    insert into public.group_memberships (group_id, dancer_id)
    values (v_wcs_group_id, v_dancer_id);
  end if;

  if not exists (
    select 1
    from public.group_memberships gm
    where gm.group_id = v_hustle_group_id
      and gm.dancer_id = v_dancer_id
      and gm.status in (
        'pending'::public.group_membership_status,
        'active'::public.group_membership_status
      )
  ) then
    insert into public.group_memberships (group_id, dancer_id)
    values (v_hustle_group_id, v_dancer_id);
  end if;

  if not exists (
    select 1
    from public.class_schedules
    where group_id = v_wcs_group_id
      and weekday = 2
      and start_time = time '19:00'
      and end_time = time '20:00'
      and active
  ) then
    perform public.admin_create_class_schedule(
      v_wcs_group_id, null::uuid, 2::smallint,
      time '19:00', time '20:00', 'Europe/Belgrade'::text,
      date '2026-09-27', null::date, null::integer,
      'members'::public.class_visibility, '{}'::uuid[]
    );
  end if;

  if not exists (
    select 1
    from public.class_schedules
    where group_id = v_wcs_group_id
      and weekday = 4
      and start_time = time '19:00'
      and end_time = time '20:00'
      and active
  ) then
    perform public.admin_create_class_schedule(
      v_wcs_group_id, null::uuid, 4::smallint,
      time '19:00', time '20:00', 'Europe/Belgrade'::text,
      date '2026-09-27', null::date, null::integer,
      'members'::public.class_visibility, '{}'::uuid[]
    );
  end if;

  if not exists (
    select 1
    from public.class_schedules
    where group_id = v_hustle_group_id
      and weekday = 5
      and start_time = time '20:00'
      and end_time = time '21:00'
      and active
  ) then
    perform public.admin_create_class_schedule(
      v_hustle_group_id, null::uuid, 5::smallint,
      time '20:00', time '21:00', 'Europe/Belgrade'::text,
      date '2026-09-27', null::date, null::integer,
      'members'::public.class_visibility, '{}'::uuid[]
    );
  end if;

  insert into public.dance_events (
    event_type, title, description, starts_at, ends_at, published, created_by
  )
  select
    'party'::public.dance_event_type,
    'Open Air',
    'Воскресный open air',
    (d + time '18:00') at time zone 'Europe/Belgrade',
    (d + time '22:00') at time zone 'Europe/Belgrade',
    true,
    v_dancer_id
  from unnest(array[
    date '2026-09-27',
    date '2026-10-04',
    date '2026-10-11',
    date '2026-10-18',
    date '2026-10-25'
  ]) as dates(d)
  where not exists (
    select 1
    from public.dance_events e
    where e.title = 'Open Air'
      and e.starts_at = (d + time '18:00') at time zone 'Europe/Belgrade'
  );

  if not exists (
    select 1
    from public.dance_events e
    where e.title = 'Halloween Party'
      and e.starts_at =
        (date '2026-10-31' + time '21:00') at time zone 'Europe/Belgrade'
  ) then
    insert into public.dance_events (
      event_type, title, description, starts_at, ends_at, published, created_by
    )
    values (
      'party'::public.dance_event_type,
      'Halloween Party',
      'Halloween party',
      (date '2026-10-31' + time '21:00') at time zone 'Europe/Belgrade',
      (date '2026-11-01' + time '02:00') at time zone 'Europe/Belgrade',
      true,
      v_dancer_id
    );
  end if;
end
$$;
