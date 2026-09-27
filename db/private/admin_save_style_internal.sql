-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: admin_save_style_internal
-- Updated:  2026-09-27T08:51:05.470Z

-- overload
-- language: plpgsql
-- args: p_style_id smallint, p_payload jsonb
-- returns: smallint

CREATE OR REPLACE FUNCTION private.admin_save_style_internal(p_style_id smallint, p_payload jsonb)
 RETURNS smallint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
