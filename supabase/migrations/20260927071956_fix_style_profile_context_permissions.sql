
create or replace function public.get_my_dancer_context()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_dancer record;
  v_roles jsonb;
  v_styles jsonb;
  v_style_catalog jsonb;
  v_dance_roles jsonb;
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

  v_styles := private.dancer_styles_context(v_dancer_id);

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
$function$;

create or replace function public.set_my_dance_style(
  p_style_id smallint,
  p_enabled boolean,
  p_main_role smallint default null::smallint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_is_partner boolean;
  v_role smallint := p_main_role;
  v_is_leader boolean;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  select s.is_partner_dance
  into v_is_partner
  from public.l_dance_style s
  where s.id = p_style_id;

  if not found then
    raise exception 'dance style not found' using errcode = 'P0002';
  end if;

  if not p_enabled then
    delete from public.dancer_style_profile
    where dancer_id = v_dancer_id
      and style_id = p_style_id;

    return public.get_my_dancer_context();
  end if;

  if coalesce(v_is_partner, true) then
    if v_role is null then
      select case when p.is_leader then 1::smallint else 2::smallint end
      into v_role
      from public.dancer_style_profile p
      where p.dancer_id = v_dancer_id
        and p.style_id = p_style_id
      order by p.is_default desc, p.created_at, p.id
      limit 1;
    end if;

    if v_role is null then
      select d.primary_role
      into v_role
      from public.dancer d
      where d.id = v_dancer_id;
    end if;

    if v_role not in (1, 2) then
      raise exception 'dance role is required for partner dance'
        using errcode = '23514';
    end if;

    v_is_leader := v_role = 1;
  else
    v_is_leader := false;
  end if;

  update public.dancer_style_profile
  set is_default = false
  where dancer_id = v_dancer_id
    and style_id = p_style_id
    and is_default;

  insert into public.dancer_style_profile (
    dancer_id,
    style_id,
    is_leader,
    is_default
  )
  values (
    v_dancer_id,
    p_style_id,
    v_is_leader,
    true
  )
  on conflict (dancer_id, style_id, is_leader)
  do update set is_default = true;

  return public.get_my_dancer_context();
end;
$function$;
