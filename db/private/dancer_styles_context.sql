-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: dancer_styles_context
-- Updated:  2026-09-27T08:01:02.277Z

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
      p.training_level_id,
      p.created_at,
      case when p.is_leader then 1::smallint else 2::smallint end as role_id,
      tl.code as training_code,
      tl.title_en as training_title_en,
      tl.title_ru as training_title_ru,
      tl.title_sr as training_title_sr,
      tl.rank_order as training_rank_order,
      (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'id', cp.id,
              'system_code', cp.system_code,
              'level_id', cp.level_id,
              'points', cp.points,
              'external_profile_id', cp.external_profile_id,
              'last_synced_at', cp.last_synced_at,
              'level', jsonb_build_object(
                'code', cl.code,
                'title_en', cl.title_en,
                'title_ru', cl.title_ru,
                'title_sr', cl.title_sr,
                'rank_order', cl.rank_order,
                'is_sport_achievement', cl.is_sport_achievement
              )
            )
            order by cp.system_code
          ),
          '[]'::jsonb
        )
        from public.dancer_style_competition_profile cp
        join public.styles_levels cl on cl.id=cp.level_id
        where cp.style_profile_id=p.id
      ) as competition_profiles
    from public.dancer_style_profile p
    left join public.styles_levels tl
      on tl.id=p.training_level_id
     and tl.style_id=p.style_id
    where p.dancer_id=p_dancer_id
  ),
  grouped as (
    select
      s.id,
      s.title_en,
      s.title_ru,
      s.title_sr,
      s.is_partner_dance,
      coalesce(
        max(p.role_id) filter(where p.is_default),
        min(p.role_id)
      ) as main_role,
      bool_or(p.is_trainer) as is_trainer,
      jsonb_agg(distinct p.role_id order by p.role_id) as role_ids,
      jsonb_agg(
        jsonb_build_object(
          'id',p.id,
          'is_leader',p.is_leader,
          'is_trainer',p.is_trainer,
          'is_default',p.is_default,
          'training_level_id',p.training_level_id,
          'training_level',
            case when p.training_level_id is null then null
            else jsonb_build_object(
              'code',p.training_code,
              'title_en',p.training_title_en,
              'title_ru',p.training_title_ru,
              'title_sr',p.training_title_sr,
              'rank_order',p.training_rank_order
            ) end,
          'competition_profiles',p.competition_profiles
        )
        order by p.is_default desc,p.is_leader desc,p.created_at
      ) as profiles
    from profiles p
    join public.l_dance_style s on s.id=p.style_id
    group by s.id,s.title_en,s.title_ru,s.title_sr,s.is_partner_dance
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',g.id,
        'title_en',g.title_en,
        'title_ru',g.title_ru,
        'title_sr',g.title_sr,
        'is_partner_dance',g.is_partner_dance,
        'main_role',g.main_role,
        'role_ids',g.role_ids,
        'is_trainer',g.is_trainer,
        'profiles',g.profiles
      )
      order by g.id
    ),
    '[]'::jsonb
  )
  from grouped g
$function$
