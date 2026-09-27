
alter table public.dancer
alter column auth_user_id drop not null;

create or replace function private.get_admin_dancers_internal()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_result jsonb;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required' using errcode='42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', d.id,
        'telegram_id', d.telegram_id,
        'telegram_username', d.telegram_username,
        'first_name', d.first_name,
        'last_name', d.last_name,
        'custom_name', d.custom_name,
        'lang_code', d.lang_code,
        'primary_role', d.primary_role,
        'auth_linked', d.auth_user_id is not null,
        'roles', coalesce((
          select jsonb_agg(r.role order by r.role)
          from public.dancer_app_roles r
          where r.dancer_id=d.id
        ), '[]'::jsonb),
        'profiles', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', p.id,
              'style_id', p.style_id,
              'is_leader', p.is_leader,
              'is_trainer', p.is_trainer,
              'is_default', p.is_default,
              'training_level_id', p.training_level_id,
              'competition_profiles', coalesce((
                select jsonb_agg(
                  jsonb_build_object(
                    'id', cp.id,
                    'system_code', cp.system_code,
                    'level_id', cp.level_id,
                    'points', cp.points,
                    'external_profile_id', cp.external_profile_id,
                    'last_synced_at', cp.last_synced_at
                  )
                  order by cp.system_code
                )
                from public.dancer_style_competition_profile cp
                where cp.style_profile_id=p.id
              ), '[]'::jsonb)
            )
            order by p.style_id, p.is_default desc, p.is_leader desc
          )
          from public.dancer_style_profile p
          where p.dancer_id=d.id
        ), '[]'::jsonb)
      )
      order by coalesce(
        nullif(btrim(d.custom_name),''),
        nullif(btrim(concat_ws(' ',d.first_name,d.last_name)),''),
        d.telegram_username,
        d.id::text
      )
    ),
    '[]'::jsonb
  )
  into v_result
  from public.dancer d;

  return v_result;
end;
$function$;

revoke all on function private.get_admin_dancers_internal()
from public,anon,authenticated;
grant execute on function private.get_admin_dancers_internal()
to authenticated;

create or replace function public.get_admin_dancers()
returns jsonb
language sql
stable
security invoker
set search_path=''
as $function$
  select private.get_admin_dancers_internal()
$function$;

revoke all on function public.get_admin_dancers()
from public,anon;
grant execute on function public.get_admin_dancers()
to authenticated;

create or replace function private.admin_save_dancer_internal(
  p_dancer_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
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
    set telegram_id=v_telegram_id,
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
$function$;

revoke all on function private.admin_save_dancer_internal(uuid,jsonb)
from public,anon,authenticated;
grant execute on function private.admin_save_dancer_internal(uuid,jsonb)
to authenticated;

create or replace function public.admin_save_dancer(
  p_dancer_id uuid,
  p_payload jsonb
)
returns uuid
language sql
security invoker
set search_path=''
as $function$
  select private.admin_save_dancer_internal(p_dancer_id,p_payload)
$function$;

revoke all on function public.admin_save_dancer(uuid,jsonb)
from public,anon;
grant execute on function public.admin_save_dancer(uuid,jsonb)
to authenticated;
