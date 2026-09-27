-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: refresh_group_title
-- Updated:  2026-09-27T07:41:05.332Z

-- overload
-- language: sql
-- args: p_group_id uuid
-- returns: void

CREATE OR REPLACE FUNCTION private.refresh_group_title(p_group_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update public.dance_group g
  set title = private.group_generated_title(
    g.id,
    g.style_id,
    g.level_id
  )
  where g.id = p_group_id
$function$
