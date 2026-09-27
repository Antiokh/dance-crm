create table if not exists public.dancer_style_roles (
  dancer_id uuid not null references public.dancer(id) on delete cascade,
  style_id smallint not null references public.l_dance_style(id) on delete cascade,
  role_id smallint not null references public.l_dance_role(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (dancer_id, style_id, role_id)
);

alter table public.dancer_style_roles enable row level security;

grant select on public.dancer_style_roles to authenticated;

drop policy if exists dancer_style_roles_select_own on public.dancer_style_roles;
create policy dancer_style_roles_select_own
on public.dancer_style_roles
for select
to authenticated
using (dancer_id = private.current_dancer_id());

do $$
declare
  v_style record;
begin
  for v_style in
    select id, table_name
    from public.l_dance_style
    where table_name is not null
      and table_name ~ '^dancer_[a-z0-9_]+$'
  loop
    execute format(
      'update public.%I t
       set main_role = d.primary_role
       from public.dancer d
       where d.id = t.id
         and t.main_role is null
         and d.primary_role is not null',
      v_style.table_name
    );

    execute format(
      'insert into public.dancer_style_roles (dancer_id, style_id, role_id)
       select id, %s::smallint, main_role
       from public.%I
       where main_role is not null
       on conflict do nothing',
      v_style.id,
      v_style.table_name
    );
  end loop;
end
$$;

insert into public.dancer_style_roles (dancer_id, style_id, role_id)
select d.id, s.id, 1::smallint
from public.dancer d
join public.l_dance_style s on s.title_en = 'West-Coast Swing'
where d.telegram_username = 'Jellu_jane'
on conflict do nothing;

CREATE OR REPLACE FUNCTION private.default_dance_role_for_style(p_dancer_id uuid, p_style_id smallint)
 RETURNS smallint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_table_name text;
  v_role smallint;
begin
  select s.table_name
  into v_table_name
  from public.l_dance_style s
  where s.id = p_style_id;

  if v_table_name is not null
    and v_table_name ~ '^dancer_[a-z0-9_]+$'
  then
    execute format(
      'select main_role from public.%I where id = $1',
      v_table_name
    )
    into v_role
    using p_dancer_id;
  end if;

  if v_role is null then
    select dsr.role_id
    into v_role
    from public.dancer_style_roles dsr
    where dsr.dancer_id = p_dancer_id
      and dsr.style_id = p_style_id
    order by dsr.role_id
    limit 1;
  end if;

  if v_role is null then
    select d.primary_role
    into v_role
    from public.dancer d
    where d.id = p_dancer_id;
  end if;

  return v_role;
end;
$function$
;

revoke all on function private.default_dance_role_for_style(uuid, smallint) from public;
revoke all on function private.default_dance_role_for_style(uuid, smallint) from anon;
revoke all on function private.default_dance_role_for_style(uuid, smallint) from authenticated;

CREATE OR REPLACE FUNCTION private.dancer_can_use_role_for_style(p_dancer_id uuid, p_style_id smallint, p_role_id smallint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    when exists (
      select 1
      from public.dancer_style_roles all_roles
      where all_roles.dancer_id = p_dancer_id
        and all_roles.style_id = p_style_id
    )
    then exists (
      select 1
      from public.dancer_style_roles allowed_role
      where allowed_role.dancer_id = p_dancer_id
        and allowed_role.style_id = p_style_id
        and allowed_role.role_id = p_role_id
    )
    else p_role_id = private.default_dance_role_for_style(
      p_dancer_id,
      p_style_id
    )
  end
$function$
;

revoke all on function private.dancer_can_use_role_for_style(uuid, smallint, smallint) from public;
revoke all on function private.dancer_can_use_role_for_style(uuid, smallint, smallint) from anon;
revoke all on function private.dancer_can_use_role_for_style(uuid, smallint, smallint) from authenticated;

CREATE OR REPLACE FUNCTION private.book_class_slot_for_current(p_slot_id uuid, p_dance_role_id smallint DEFAULT NULL::smallint)
 RETURNS bookings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_slot record;
  v_partner boolean;
  v_role smallint := p_dance_role_id;
  v_capacity integer;
  v_booked_count integer;
  v_status public.booking_status;
  v_booking public.bookings%rowtype;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found'
      using errcode='P0002';
  end if;

  select cs.*, g.style_id
  into v_slot
  from public.class_slots cs
  join public.dance_group g on g.id = cs.group_id
  where cs.id = p_slot_id
  for update of cs;

  if not found then
    raise exception 'class slot not found'
      using errcode='P0002';
  end if;

  if not private.can_view_class(v_slot.group_id, v_slot.visibility) then
    raise exception 'class slot access denied'
      using errcode='42501';
  end if;

  if v_slot.status <> 'scheduled'::public.class_slot_status then
    raise exception 'class slot is not bookable'
      using errcode='23514';
  end if;

  if v_slot.starts_at <= now() then
    raise exception 'class slot has already started'
      using errcode='23514';
  end if;

  select *
  into v_booking
  from public.bookings b
  where b.slot_id = p_slot_id
    and b.dancer_id = v_dancer_id
  for update;

  if found and v_booking.status <> 'cancelled'::public.booking_status then
    raise exception 'booking already exists for this class'
      using errcode='23505';
  end if;

  select s.is_partner_dance
  into v_partner
  from public.l_dance_style s
  where s.id = v_slot.style_id;

  if coalesce(v_partner, true) then
    if v_role is null then
      v_role := private.default_dance_role_for_style(
        v_dancer_id,
        v_slot.style_id
      );
    end if;

    if v_role is null or not exists (
      select 1
      from public.l_dance_role r
      where r.id = v_role
    ) then
      raise exception 'dance role is required for partner dance'
        using errcode='23514';
    end if;

    if not private.dancer_can_use_role_for_style(
      v_dancer_id,
      v_slot.style_id,
      v_role
    ) then
      raise exception 'dance role is not enabled for this style'
        using errcode='23514';
    end if;
  else
    v_role := null;
  end if;

  v_capacity := private.effective_slot_capacity(p_slot_id);

  select count(*)::integer
  into v_booked_count
  from public.bookings
  where slot_id = p_slot_id
    and status = 'booked'::public.booking_status;

  if v_capacity is not null and v_booked_count >= v_capacity then
    v_status := 'waitlisted'::public.booking_status;
  else
    v_status := 'booked'::public.booking_status;
  end if;

  if v_booking.id is not null then
    update public.bookings
    set status = v_status,
        attendance_status = null,
        dance_role_id = v_role,
        is_trial = false,
        booked_at = now(),
        cancelled_at = null,
        cancellation_type = null
    where id = v_booking.id
    returning * into v_booking;
  else
    insert into public.bookings (
      slot_id,
      dancer_id,
      status,
      dance_role_id,
      is_trial
    )
    values (
      p_slot_id,
      v_dancer_id,
      v_status,
      v_role,
      false
    )
    returning * into v_booking;
  end if;

  perform private.sync_overbook_request_for_booking(v_booking.id);

  return v_booking;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_dancer_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_dancer record;
  v_roles jsonb;
  v_styles jsonb := '[]'::jsonb;
  v_style_catalog jsonb;
  v_dance_roles jsonb;
  v_style record;
  v_style_data jsonb;
  v_style_role_ids jsonb;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  select
    d.id,
    d.telegram_username,
    d.first_name,
    d.last_name,
    d.custom_name,
    d.lang_code,
    d.primary_role
  into v_dancer
  from public.dancer d
  where d.id = v_dancer_id;

  select coalesce(jsonb_agg(r.role order by r.role), '[]'::jsonb)
  into v_roles
  from public.dancer_app_roles r
  where r.dancer_id = v_dancer_id;

  for v_style in
    select *
    from public.l_dance_style
    order by id
  loop
    if v_style.table_name is null
      or v_style.table_name !~ '^dancer_[a-z0-9_]+$'
    then
      continue;
    end if;

    execute format(
      'select to_jsonb(t) - %L - %L from public.%I t where t.id = $1',
      'id',
      'created_at',
      v_style.table_name
    )
    into v_style_data
    using v_dancer_id;

    if v_style_data is not null then
      select coalesce(
        jsonb_agg(dsr.role_id order by dsr.role_id),
        '[]'::jsonb
      )
      into v_style_role_ids
      from public.dancer_style_roles dsr
      where dsr.dancer_id = v_dancer_id
        and dsr.style_id = v_style.id;

      v_styles := v_styles || jsonb_build_array(
        jsonb_build_object(
          'id', v_style.id,
          'title_en', v_style.title_en,
          'title_ru', v_style.title_ru,
          'title_sr', v_style.title_sr,
          'is_partner_dance', v_style.is_partner_dance,
          'role_ids', v_style_role_ids
        ) || v_style_data
      );
    end if;
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'title_en', s.title_en,
        'title_ru', s.title_ru,
        'title_sr', s.title_sr,
        'is_partner_dance', s.is_partner_dance
      )
      order by s.id
    ),
    '[]'::jsonb
  )
  into v_style_catalog
  from public.l_dance_style s;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'title_en', r.title_en,
        'title_ru', r.title_ru,
        'title_sr', r.title_sr
      )
      order by r.id
    ),
    '[]'::jsonb
  )
  into v_dance_roles
  from public.l_dance_role r;

  return jsonb_build_object(
    'dancer', jsonb_build_object(
      'id', v_dancer.id,
      'telegram_username', v_dancer.telegram_username,
      'first_name', v_dancer.first_name,
      'last_name', v_dancer.last_name,
      'custom_name', v_dancer.custom_name,
      'lang_code', v_dancer.lang_code,
      'primary_role', v_dancer.primary_role
    ),
    'roles', v_roles,
    'styles', v_styles,
    'style_catalog', v_style_catalog,
    'dance_roles', v_dance_roles
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.telegram_auth_bootstrap(p_telegram_id bigint, p_password text, p_user_meta_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.dancer%rowtype;
  v_dancer public.dancer%rowtype;
  v_user_id uuid;
  v_created boolean := false;
  v_roles jsonb;
  v_styles jsonb := '[]'::jsonb;
  v_style_catalog jsonb;
  v_dance_roles jsonb;
  v_style record;
  v_style_data jsonb;
  v_style_role_ids jsonb;
begin
  if p_telegram_id is null or p_telegram_id <= 0 then
    raise exception 'invalid telegram id' using errcode = '22023';
  end if;

  if p_password is null or length(p_password) < 24 then
    raise exception 'invalid auth password' using errcode = '22023';
  end if;

  select *
  into v_existing
  from public.dancer
  where telegram_id = p_telegram_id
  for update;

  if found and v_existing.auth_user_id is not null then
    v_user_id := v_existing.auth_user_id;
    perform public.update_user_password(v_user_id, p_password);
  else
    v_user_id := public.create_user_telegram_metadata(
      p_telegram_id,
      p_password,
      coalesce(p_user_meta_data, '{}'::jsonb)
    );
    v_created := true;

    if v_existing.id is not null then
      update public.dancer
      set auth_user_id = v_user_id
      where id = v_existing.id
        and auth_user_id is null;
    end if;
  end if;

  select *
  into v_dancer
  from public.ensure_dancer_exists(v_user_id);

  if v_dancer.id is null then
    raise exception 'failed to ensure dancer profile' using errcode = 'P0002';
  end if;

  update public.dancer
  set telegram_username = nullif(p_user_meta_data->>'username', ''),
      first_name = nullif(p_user_meta_data->>'first_name', ''),
      last_name = nullif(p_user_meta_data->>'last_name', ''),
      lang_code = coalesce(
        nullif(p_user_meta_data->>'language_code', ''),
        lang_code
      ),
      tg_user_json = coalesce(p_user_meta_data, tg_user_json)
  where id = v_dancer.id
  returning * into v_dancer;

  select coalesce(jsonb_agg(r.role order by r.role), '[]'::jsonb)
  into v_roles
  from public.dancer_app_roles r
  where r.dancer_id = v_dancer.id;

  for v_style in
    select *
    from public.l_dance_style
    order by id
  loop
    if v_style.table_name is null
      or v_style.table_name !~ '^dancer_[a-z0-9_]+$'
    then
      continue;
    end if;

    execute format(
      'select to_jsonb(t) - %L - %L from public.%I t where t.id = $1',
      'id',
      'created_at',
      v_style.table_name
    )
    into v_style_data
    using v_dancer.id;

    if v_style_data is not null then
      select coalesce(
        jsonb_agg(dsr.role_id order by dsr.role_id),
        '[]'::jsonb
      )
      into v_style_role_ids
      from public.dancer_style_roles dsr
      where dsr.dancer_id = v_dancer.id
        and dsr.style_id = v_style.id;

      v_styles := v_styles || jsonb_build_array(
        jsonb_build_object(
          'id', v_style.id,
          'title_en', v_style.title_en,
          'title_ru', v_style.title_ru,
          'title_sr', v_style.title_sr,
          'is_partner_dance', v_style.is_partner_dance,
          'role_ids', v_style_role_ids
        ) || v_style_data
      );
    end if;
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'title_en', s.title_en,
        'title_ru', s.title_ru,
        'title_sr', s.title_sr,
        'is_partner_dance', s.is_partner_dance
      )
      order by s.id
    ),
    '[]'::jsonb
  )
  into v_style_catalog
  from public.l_dance_style s;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'title_en', r.title_en,
        'title_ru', r.title_ru,
        'title_sr', r.title_sr
      )
      order by r.id
    ),
    '[]'::jsonb
  )
  into v_dance_roles
  from public.l_dance_role r;

  return jsonb_build_object(
    'created', v_created,
    'auth_email', p_telegram_id::text || '@t.me',
    'dancer_id', v_dancer.id,
    'context', jsonb_build_object(
      'dancer', jsonb_build_object(
        'id', v_dancer.id,
        'telegram_id', v_dancer.telegram_id,
        'telegram_username', v_dancer.telegram_username,
        'first_name', v_dancer.first_name,
        'last_name', v_dancer.last_name,
        'custom_name', v_dancer.custom_name,
        'lang_code', v_dancer.lang_code,
        'premium', v_dancer.premium,
        'primary_role', v_dancer.primary_role
      ),
      'roles', v_roles,
      'styles', v_styles,
      'style_catalog', v_style_catalog,
      'dance_roles', v_dance_roles
    )
  );
end;
$function$
;
