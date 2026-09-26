-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: bootstrap_functions_to_github
-- Updated:  2026-09-26T20:50:20.850Z

-- overload
-- language: plpgsql
-- args: p_schema text DEFAULT 'public'::text, p_immediate_limit integer DEFAULT 50
-- returns: integer

CREATE OR REPLACE FUNCTION archive.bootstrap_functions_to_github(p_schema text DEFAULT 'public'::text, p_immediate_limit integer DEFAULT 50)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_count integer;
begin
  insert into archive.github_push_queue(function_history_id)
  select id
  from archive.function_history
  where schema_name = p_schema
    and active = true
  on conflict (function_history_id) do nothing;

  get diagnostics v_count = row_count;

  if p_immediate_limit > 0 then
    perform archive.process_github_push_queue(p_immediate_limit);
  end if;

  return v_count;
end;
$function$
