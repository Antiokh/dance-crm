-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: update_my_dancer_profile
-- Updated:  2026-09-26T20:35:19.901Z

-- overload
-- language: plpgsql
-- args: p_custom_name text DEFAULT NULL::text, p_primary_role smallint DEFAULT NULL::smallint, p_lang_code text DEFAULT NULL::text
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.update_my_dancer_profile(p_custom_name text DEFAULT NULL::text, p_primary_role smallint DEFAULT NULL::smallint, p_lang_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  if p_primary_role is not null
    and not exists (
      select 1 from public.l_dance_role r where r.id = p_primary_role
    )
  then
    raise exception 'invalid dance role' using errcode = '22023';
  end if;

  update public.dancer
  set custom_name = nullif(btrim(p_custom_name), ''),
      primary_role = p_primary_role,
      lang_code = coalesce(nullif(btrim(p_lang_code), ''), lang_code)
  where id = v_dancer_id;

  if not found then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  return public.get_my_dancer_context();
end;
$function$
