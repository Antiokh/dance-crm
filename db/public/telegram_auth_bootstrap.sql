-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: telegram_auth_bootstrap
-- Updated:  2026-09-27T06:51:08.309Z

-- overload
-- language: plpgsql
-- args: p_telegram_id bigint, p_password text, p_user_meta_data jsonb
-- returns: jsonb

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
