-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: ensure_dancer_exists
-- Updated:  2026-09-26T20:34:44.608Z

-- overload
-- language: plpgsql
-- args: p_user_id uuid
-- returns: dancer

CREATE OR REPLACE FUNCTION public.ensure_dancer_exists(p_user_id uuid)
 RETURNS dancer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user auth.users%rowtype;
  v_dancer public.dancer%rowtype;
  v_telegram_id bigint;
begin
  select *
  into v_user
  from auth.users
  where id = p_user_id;

  if not found then
    return null;
  end if;

  begin
    v_telegram_id := nullif(
      v_user.raw_user_meta_data->>'telegram_id',
      ''
    )::bigint;
  exception when others then
    v_telegram_id := null;
  end;

  if v_telegram_id is null then
    raise exception 'telegram id missing from auth metadata'
      using errcode='22023';
  end if;

  select *
  into v_dancer
  from public.dancer
  where auth_user_id = p_user_id;

  if not found then
    select *
    into v_dancer
    from public.dancer
    where telegram_id = v_telegram_id
    for update;
  end if;

  if found then
    if v_dancer.auth_user_id <> p_user_id then
      raise exception 'telegram dancer is linked to a different auth user'
        using errcode='23505';
    end if;

    update public.dancer
    set telegram_username = nullif(v_user.raw_user_meta_data->>'username', ''),
        first_name = nullif(v_user.raw_user_meta_data->>'first_name', ''),
        last_name = nullif(v_user.raw_user_meta_data->>'last_name', ''),
        lang_code = coalesce(
          nullif(v_user.raw_user_meta_data->>'language_code', ''),
          lang_code
        ),
        tg_user_json = coalesce(v_user.raw_user_meta_data, tg_user_json)
    where id = v_dancer.id
    returning * into v_dancer;
  else
    insert into public.dancer (
      id,
      auth_user_id,
      telegram_id,
      first_name,
      last_name,
      telegram_username,
      tg_user_json,
      lang_code
    )
    values (
      extensions.gen_random_uuid(),
      p_user_id,
      v_telegram_id,
      nullif(v_user.raw_user_meta_data->>'first_name', ''),
      nullif(v_user.raw_user_meta_data->>'last_name', ''),
      nullif(v_user.raw_user_meta_data->>'username', ''),
      coalesce(v_user.raw_user_meta_data, '{}'::jsonb),
      coalesce(
        nullif(v_user.raw_user_meta_data->>'language_code', ''),
        'en'
      )
    )
    returning * into v_dancer;
  end if;

  insert into public.dancer_app_roles (dancer_id, role)
  values (v_dancer.id, 'dancer'::public.app_role)
  on conflict do nothing;

  return v_dancer;
end;
$function$
