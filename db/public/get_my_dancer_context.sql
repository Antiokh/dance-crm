-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_my_dancer_context
-- Updated:  2026-09-27T07:21:09.661Z

-- overload
-- language: plpgsql
-- args: 
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.get_my_dancer_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_dancer record;
  v_roles jsonb;
  v_styles jsonb;
  v_style_catalog jsonb;
  v_dance_roles jsonb;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  select
    d.id,
    d.telegram_username,
    d.first_name,
    d.last_name,
    d.custom_name,
    d.lang_code,
    d.primary_role
  into v_dancer
  from public.dancer d
  where d.id = v_dancer_id;

  select coalesce(jsonb_agg(r.role order by r.role), '[]'::jsonb)
  into v_roles
  from public.dancer_app_roles r
  where r.dancer_id = v_dancer_id;

  v_styles := private.dancer_styles_context(v_dancer_id);

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
    'dancer', jsonb_build_object(
      'id', v_dancer.id,
      'telegram_username', v_dancer.telegram_username,
      'first_name', v_dancer.first_name,
      'last_name', v_dancer.last_name,
      'custom_name', v_dancer.custom_name,
      'lang_code', v_dancer.lang_code,
      'primary_role', v_dancer.primary_role
    ),
    'roles', v_roles,
    'styles', v_styles,
    'style_catalog', v_style_catalog,
    'dance_roles', v_dance_roles
  );
end;
$function$
