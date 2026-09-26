-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_dancer_styles
-- Updated:  2026-09-26T20:35:39.345Z

-- overload
-- language: plpgsql
-- args: p_id uuid
-- returns: jsonb[]

CREATE OR REPLACE FUNCTION public.get_dancer_styles(p_id uuid)
 RETURNS jsonb[]
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'information_schema'
AS $function$
declare
  rec record;
  result jsonb[];
  query text;
  exists boolean;
  fetched jsonb;
begin
  for rec in select * from public.l_dance_style loop
    if rec.table_name is null then
      continue;
    end if;

    -- Check if the table exists
    select exists (
      select 1 from information_schema.tables 
      where table_schema = 'public' and table_name = rec.table_name
    ) into exists;

    if exists then
      query := format(
        'select to_jsonb(t) - %L - %L from public.%I t where id = $1',
        'id', 'created_at', rec.table_name
      );

      execute query into fetched using p_id;

      if fetched is not null then
        result := array_append(result, to_jsonb(rec) || fetched);
      end if;
    end if;
  end loop;

  return coalesce(result, '{}');
end;
$function$
