-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: default_dance_role_for_style
-- Updated:  2026-09-26T20:33:33.410Z

-- overload
-- language: plpgsql
-- args: p_dancer_id uuid, p_style_id smallint
-- returns: smallint

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
    select d.primary_role
    into v_role
    from public.dancer d
    where d.id = p_dancer_id;
  end if;

  return v_role;
end;
$function$
