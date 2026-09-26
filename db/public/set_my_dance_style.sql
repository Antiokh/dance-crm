-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: set_my_dance_style
-- Updated:  2026-09-26T20:35:21.258Z

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
  v_auth_user_id uuid := auth.uid();
  v_dancer_id uuid;
  v_table_name text;
  v_is_partner boolean;
  v_role smallint := p_main_role;
begin
  if v_auth_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select d.id
  into v_dancer_id
  from public.dancer d
  where d.auth_user_id = v_auth_user_id;

  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  select s.table_name, s.is_partner_dance
  into v_table_name, v_is_partner
  from public.l_dance_style s
  where s.id = p_style_id;

  if v_table_name is null or v_table_name !~ '^dancer_[a-z0-9_]+$' then
    raise exception 'invalid style table' using errcode = '22023';
  end if;

  if not coalesce(v_is_partner, true) then
    v_role := null;
  elsif v_role is not null
    and not exists (
      select 1 from public.l_dance_role r where r.id = v_role
    )
  then
    raise exception 'invalid dance role' using errcode = '22023';
  end if;

  if p_enabled then
    execute format(
      'insert into public.%I (id, main_role)
       values ($1, $2)
       on conflict (id) do update set main_role = excluded.main_role',
      v_table_name
    )
    using v_dancer_id, v_role;
  else
    execute format(
      'delete from public.%I where id = $1',
      v_table_name
    )
    using v_dancer_id;
  end if;

  return public.get_my_dancer_context();
end;
$function$
