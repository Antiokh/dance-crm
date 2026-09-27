-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: dancer_styles_context
-- Updated:  2026-09-27T07:21:06.853Z

-- overload
-- language: sql
-- args: p_dancer_id uuid
-- returns: jsonb

CREATE OR REPLACE FUNCTION private.dancer_styles_context(p_dancer_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with profiles as (
    select
      p.id,
      p.dancer_id,
      p.style_id,
      p.is_leader,
      p.is_trainer,
      p.is_default,
      p.level_id,
      p.created_at,
      case when p.is_leader then 1::smallint else 2::smallint end as role_id,
      l.code as level_code,
      l.title_en as level_title_en,
      l.title_ru as level_title_ru,
      l.title_sr as level_title_sr,
      l.rank_order as level_rank_order
    from public.dancer_style_profile p
    left join public.styles_levels l
      on l.id = p.level_id
     and l.style_id = p.style_id
    where p.dancer_id = p_dancer_id
  ),
  grouped as (
    select
      s.id,
      s.title_en,
      s.title_ru,
      s.title_sr,
      s.is_partner_dance,
      coalesce(
        max(p.role_id) filter (where p.is_default),
        min(p.role_id)
      ) as main_role,
      bool_or(p.is_trainer) as is_trainer,
      jsonb_agg(
        distinct p.role_id
        order by p.role_id
      ) as role_ids,
      jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'is_leader', p.is_leader,
          'is_trainer', p.is_trainer,
          'is_default', p.is_default,
          'level_id', p.level_id,
          'level',
            case
              when p.level_id is null then null
              else jsonb_build_object(
                'code', p.level_code,
                'title_en', p.level_title_en,
                'title_ru', p.level_title_ru,
                'title_sr', p.level_title_sr,
                'rank_order', p.level_rank_order
              )
            end
        )
        order by p.is_default desc, p.is_leader desc, p.created_at
      ) as profiles
    from profiles p
    join public.l_dance_style s on s.id = p.style_id
    group by
      s.id,
      s.title_en,
      s.title_ru,
      s.title_sr,
      s.is_partner_dance
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', g.id,
        'title_en', g.title_en,
        'title_ru', g.title_ru,
        'title_sr', g.title_sr,
        'is_partner_dance', g.is_partner_dance,
        'main_role', g.main_role,
        'role_ids', g.role_ids,
        'is_trainer', g.is_trainer,
        'profiles', g.profiles
      )
      order by g.id
    ),
    '[]'::jsonb
  )
  from grouped g
$function$
