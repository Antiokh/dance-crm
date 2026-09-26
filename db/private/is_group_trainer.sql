-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: is_group_trainer
-- Updated:  2026-09-26T20:34:03.172Z

-- overload
-- language: sql
-- args: p_group_id uuid
-- returns: boolean

CREATE OR REPLACE FUNCTION private.is_group_trainer(p_group_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.group_trainers gt
    where gt.group_id = p_group_id
      and gt.trainer_id = private.current_dancer_id()
      and (gt.starts_on is null or gt.starts_on <= current_date)
      and (gt.ends_on is null or gt.ends_on >= current_date)
  )
$function$
