-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: set_dancer
-- Updated:  2026-09-26T20:35:18.630Z

-- overload
-- language: plpgsql
-- args: id uuid, tablename text, state boolean
-- returns: void

CREATE OR REPLACE FUNCTION public.set_dancer(id uuid, tablename text, state boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
    if state then
        execute format('insert into %I (id) values ($1) on conflict (id) do nothing', tablename) using id;
    else
        execute format('delete from %I where id = $1', tablename) using id;
    end if;
end;
$function$
