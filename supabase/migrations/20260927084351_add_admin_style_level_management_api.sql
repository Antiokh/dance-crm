
create or replace function private.admin_save_style_internal(
  p_style_id smallint,
  p_payload jsonb
)
returns smallint
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_style_id smallint := p_style_id;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required' using errcode='42501';
  end if;

  if v_style_id is null then
    lock table public.l_dance_style in exclusive mode;
    select (coalesce(max(id),0)+1)::smallint
    into v_style_id
    from public.l_dance_style;

    insert into public.l_dance_style(
      id,title_en,title_ru,title_sr,is_partner_dance
    )
    values(
      v_style_id,
      nullif(btrim(p_payload->>'title_en'),''),
      nullif(btrim(p_payload->>'title_ru'),''),
      nullif(btrim(p_payload->>'title_sr'),''),
      coalesce((p_payload->>'is_partner_dance')::boolean,true)
    );
  else
    update public.l_dance_style
    set title_en=nullif(btrim(p_payload->>'title_en'),''),
        title_ru=nullif(btrim(p_payload->>'title_ru'),''),
        title_sr=nullif(btrim(p_payload->>'title_sr'),''),
        is_partner_dance=coalesce(
          (p_payload->>'is_partner_dance')::boolean,
          is_partner_dance
        )
    where id=v_style_id;

    if not found then
      raise exception 'dance style not found' using errcode='P0002';
    end if;
  end if;

  return v_style_id;
end;
$function$;

revoke all on function private.admin_save_style_internal(smallint,jsonb)
from public,anon,authenticated;
grant execute on function private.admin_save_style_internal(smallint,jsonb)
to authenticated;

create or replace function public.admin_save_style(
  p_style_id smallint,
  p_payload jsonb
)
returns smallint
language sql
security invoker
set search_path=''
as $function$
  select private.admin_save_style_internal(p_style_id,p_payload)
$function$;

revoke all on function public.admin_save_style(smallint,jsonb)
from public,anon;
grant execute on function public.admin_save_style(smallint,jsonb)
to authenticated;

create or replace function private.admin_save_level_internal(
  p_level_id bigint,
  p_payload jsonb
)
returns bigint
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_level_id bigint := p_level_id;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required' using errcode='42501';
  end if;

  if v_level_id is null then
    insert into public.styles_levels(
      style_id,code,title_en,title_ru,title_sr,rank_order,active,kind,
      system_code,is_sport_achievement,description
    )
    values(
      (p_payload->>'style_id')::smallint,
      btrim(p_payload->>'code'),
      btrim(p_payload->>'title_en'),
      nullif(btrim(p_payload->>'title_ru'),''),
      nullif(btrim(p_payload->>'title_sr'),''),
      coalesce((p_payload->>'rank_order')::smallint,0),
      coalesce((p_payload->>'active')::boolean,true),
      coalesce(nullif(btrim(p_payload->>'kind'),''),'training'),
      coalesce(nullif(btrim(p_payload->>'system_code'),''),'school'),
      coalesce((p_payload->>'is_sport_achievement')::boolean,false),
      nullif(btrim(p_payload->>'description'),'')
    )
    returning id into v_level_id;
  else
    update public.styles_levels
    set style_id=(p_payload->>'style_id')::smallint,
        code=btrim(p_payload->>'code'),
        title_en=btrim(p_payload->>'title_en'),
        title_ru=nullif(btrim(p_payload->>'title_ru'),''),
        title_sr=nullif(btrim(p_payload->>'title_sr'),''),
        rank_order=coalesce((p_payload->>'rank_order')::smallint,rank_order),
        active=coalesce((p_payload->>'active')::boolean,active),
        kind=coalesce(nullif(btrim(p_payload->>'kind'),''),kind),
        system_code=coalesce(
          nullif(btrim(p_payload->>'system_code'),''),
          system_code
        ),
        is_sport_achievement=coalesce(
          (p_payload->>'is_sport_achievement')::boolean,
          is_sport_achievement
        ),
        description=nullif(btrim(p_payload->>'description'),'')
    where id=v_level_id;

    if not found then
      raise exception 'style level not found' using errcode='P0002';
    end if;
  end if;

  return v_level_id;
end;
$function$;

revoke all on function private.admin_save_level_internal(bigint,jsonb)
from public,anon,authenticated;
grant execute on function private.admin_save_level_internal(bigint,jsonb)
to authenticated;

create or replace function public.admin_save_level(
  p_level_id bigint,
  p_payload jsonb
)
returns bigint
language sql
security invoker
set search_path=''
as $function$
  select private.admin_save_level_internal(p_level_id,p_payload)
$function$;

revoke all on function public.admin_save_level(bigint,jsonb)
from public,anon;
grant execute on function public.admin_save_level(bigint,jsonb)
to authenticated;
