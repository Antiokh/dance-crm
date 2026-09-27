-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: set_my_dance_style
-- Updated:  2026-09-27T07:22:00.387Z

-- overload
-- language: plpgsql
-- args: p_style_id smallint, p_enabled boolean, p_main_role smallint DEFAULT NULL::smallint
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.set_my_dance_style(p_style_id smallint, p_enabled boolean, p_main_role smallint DEFAULT NULL::smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
