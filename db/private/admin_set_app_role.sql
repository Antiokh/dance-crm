-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: admin_set_app_role
-- Updated:  2026-09-26T20:34:10.247Z

-- overload
-- language: plpgsql
-- args: p_dancer_id uuid, p_role app_role, p_enabled boolean
-- returns: void

CREATE OR REPLACE FUNCTION private.admin_set_app_role(p_dancer_id uuid, p_role app_role, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.current_dancer_id();
  v_admin_count integer;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required' using errcode='42501';
  end if;

  if not exists (select 1 from public.dancer d where d.id = p_dancer_id) then
    raise exception 'dancer not found' using errcode='P0002';
  end if;

  if p_role = 'dancer'::public.app_role and not p_enabled then
    raise exception 'dancer role is mandatory' using errcode='23514';
  end if;

  if p_enabled then
    insert into public.dancer_app_roles (dancer_id, role, granted_by)
    values (p_dancer_id, p_role, v_actor)
    on conflict (dancer_id, role) do update
    set granted_at = now(),
        granted_by = excluded.granted_by;
    return;
  end if;

  if p_role = 'administrator'::public.app_role then
    select count(*)::integer
    into v_admin_count
    from public.dancer_app_roles
    where role = 'administrator'::public.app_role;

    if v_admin_count <= 1 then
      raise exception 'cannot remove the last administrator'
        using errcode='23514';
    end if;
  end if;

  delete from public.dancer_app_roles
  where dancer_id = p_dancer_id
    and role = p_role;
end;
$function$
