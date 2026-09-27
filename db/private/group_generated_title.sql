-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: group_generated_title
-- Updated:  2026-09-27T07:41:01.693Z

-- overload
-- language: sql
-- args: p_group_id uuid, p_style_id smallint, p_level_id bigint
-- returns: text

CREATE OR REPLACE FUNCTION private.group_generated_title(p_group_id uuid, p_style_id smallint, p_level_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select left(
    concat_ws(
      ' · ',
      coalesce(
        nullif(btrim(s.title_en), ''),
        nullif(btrim(s.title_ru), ''),
        nullif(btrim(s.title_sr), ''),
        'Style'
      ),
      (
        select coalesce(
          nullif(btrim(l.title_en), ''),
          nullif(btrim(l.title_ru), ''),
          nullif(btrim(l.title_sr), '')
        )
        from public.styles_levels l
        where l.id = p_level_id
          and l.style_id = p_style_id
      ),
      (
        select coalesce(
          nullif(btrim(d.custom_name), ''),
          nullif(btrim(concat_ws(' ', d.first_name, d.last_name)), ''),
          case
            when nullif(btrim(d.telegram_username), '') is not null
              then '@' || btrim(d.telegram_username)
            else null
          end
        )
        from public.group_trainers gt
        join public.dancer d on d.id = gt.trainer_id
        where gt.group_id = p_group_id
          and gt.trainer_role = 'lead'::public.group_trainer_role
        order by
          (
            (gt.starts_on is null or gt.starts_on <= current_date)
            and (gt.ends_on is null or gt.ends_on >= current_date)
          ) desc,
          gt.starts_on desc nulls last,
          gt.created_at desc,
          gt.trainer_id
        limit 1
      )
    ),
    160
  )
  from public.l_dance_style s
  where s.id = p_style_id
$function$
