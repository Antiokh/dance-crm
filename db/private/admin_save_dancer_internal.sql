-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: admin_save_dancer_internal
-- Updated:  2026-09-27T09:41:01.976Z

-- overload
-- language: plpgsql
-- args: p_dancer_id uuid, p_payload jsonb
-- returns: uuid

CREATE OR REPLACE FUNCTION private.admin_save_dancer_internal(p_dancer_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := p_dancer_id;
  v_current_dancer_id uuid := private.current_dancer_id();
  v_is_administrator boolean :=
    coalesce((p_payload->>'is_administrator')::boolean,false);
  v_is_trainer boolean := false;
  v_profile jsonb;
  v_competition jsonb;
  v_profile_id uuid;
  v_telegram_id bigint;
  v_primary_role smallint;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required' using errcode='42501';
  end if;

  begin
    v_telegram_id := nullif(btrim(p_payload->>'telegram_id'),'')::bigint;
  exception when others then
    raise exception 'invalid telegram id' using errcode='22023';
  end;

  begin
    v_primary_role := nullif(btrim(p_payload->>'primary_role'),'')::smallint;
  exception when others then
    raise exception 'invalid primary role' using errcode='22023';
  end;

  if v_primary_role is not null and v_primary_role not in (1,2) then
    raise exception 'primary role must be Leader or Follower'
      using errcode='23514';
  end if;

  if v_dancer_id is null then
    insert into public.dancer(
      id,auth_user_id,telegram_id,first_name,last_name,telegram_username,
      custom_name,lang_code,primary_role,saved
    )
    values(
      extensions.gen_random_uuid(),
      null,
      v_telegram_id,
      nullif(btrim(p_payload->>'first_name'),''),
      nullif(btrim(p_payload->>'last_name'),''),
      nullif(btrim(p_payload->>'telegram_username'),''),
      nullif(btrim(p_payload->>'custom_name'),''),
      coalesce(nullif(btrim(p_payload->>'lang_code'),''),'ru'),
      v_primary_role,
      true
    )
    returning id into v_dancer_id;
  else
    if not exists(select 1 from public.dancer d where d.id=v_dancer_id) then
      raise exception 'dancer not found' using errcode='P0002';
    end if;

    update public.dancer
    set telegram_id=case
          when auth_user_id is null then v_telegram_id
          else telegram_id
        end,
        first_name=nullif(btrim(p_payload->>'first_name'),''),
        last_name=nullif(btrim(p_payload->>'last_name'),''),
        telegram_username=nullif(btrim(p_payload->>'telegram_username'),''),
        custom_name=nullif(btrim(p_payload->>'custom_name'),''),
        lang_code=coalesce(nullif(btrim(p_payload->>'lang_code'),''),lang_code),
        primary_role=v_primary_role,
        saved=true
    where id=v_dancer_id;
  end if;

  if v_dancer_id=v_current_dancer_id
    and private.has_app_role('administrator'::public.app_role)
    and not v_is_administrator
  then
    raise exception 'administrator cannot remove own administrator role'
      using errcode='23514';
  end if;

  insert into public.dancer_app_roles(dancer_id,role,granted_by)
  values(v_dancer_id,'dancer'::public.app_role,v_current_dancer_id)
  on conflict(dancer_id,role) do nothing;

  delete from public.dancer_style_profile
  where dancer_id=v_dancer_id;

  for v_profile in
    select value
    from jsonb_array_elements(coalesce(p_payload->'profiles','[]'::jsonb))
  loop
    insert into public.dancer_style_profile(
      dancer_id,style_id,is_leader,is_trainer,is_default,training_level_id
    )
    values(
      v_dancer_id,
      (v_profile->>'style_id')::smallint,
      coalesce((v_profile->>'is_leader')::boolean,false),
      coalesce((v_profile->>'is_trainer')::boolean,false),
      coalesce((v_profile->>'is_default')::boolean,false),
      nullif(v_profile->>'training_level_id','')::bigint
    )
    returning id into v_profile_id;

    if coalesce((v_profile->>'is_trainer')::boolean,false) then
      v_is_trainer := true;
    end if;

    for v_competition in
      select value
      from jsonb_array_elements(
        coalesce(v_profile->'competition_profiles','[]'::jsonb)
      )
    loop
      insert into public.dancer_style_competition_profile(
        style_profile_id,system_code,level_id,points,external_profile_id,last_synced_at
      )
      values(
        v_profile_id,
        nullif(btrim(v_competition->>'system_code'),''),
        nullif(v_competition->>'level_id','')::bigint,
        nullif(v_competition->>'points','')::numeric,
        nullif(btrim(v_competition->>'external_profile_id'),''),
        nullif(v_competition->>'last_synced_at','')::timestamptz
      );
    end loop;
  end loop;

  delete from public.dancer_app_roles
  where dancer_id=v_dancer_id
    and role in ('trainer'::public.app_role,'administrator'::public.app_role);

  if v_is_trainer then
    insert into public.dancer_app_roles(dancer_id,role,granted_by)
    values(v_dancer_id,'trainer'::public.app_role,v_current_dancer_id)
    on conflict(dancer_id,role) do nothing;
  end if;

  if v_is_administrator then
    insert into public.dancer_app_roles(dancer_id,role,granted_by)
    values(v_dancer_id,'administrator'::public.app_role,v_current_dancer_id)
    on conflict(dancer_id,role) do nothing;
  end if;

  return v_dancer_id;
end;
$function$
