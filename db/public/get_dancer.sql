-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_dancer
-- Updated:  2026-09-26T20:35:29.286Z

-- overload
-- language: plpgsql
-- args: p_id uuid
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.get_dancer(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  dancer_data jsonb;
  styles jsonb[];
begin
  -- Fetch the dancer record
  select to_jsonb(d) from public.dancer d where d.id = p_id into dancer_data;

  if dancer_data is null then
    return null;
  end if;

  -- Get styles using previously defined function
  styles := public.get_dancer_styles(p_id);

  -- Append styles as a new key
  dancer_data := dancer_data || jsonb_build_object('styles', styles);

  return dancer_data;
end;
$function$
