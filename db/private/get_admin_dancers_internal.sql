-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: get_admin_dancers_internal
-- Updated:  2026-09-27T08:51:02.328Z

-- overload
-- language: plpgsql
-- args: 
-- returns: jsonb

CREATE OR REPLACE FUNCTION private.get_admin_dancers_internal()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
