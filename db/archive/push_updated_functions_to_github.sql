-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: push_updated_functions_to_github
-- Updated:  2026-09-26T20:33:22.518Z

-- overload
-- language: plpgsql
-- args: p_schema text DEFAULT 'public'::text, p_immediate_limit integer DEFAULT 40
-- returns: integer

CREATE OR REPLACE FUNCTION archive.push_updated_functions_to_github(p_schema text DEFAULT 'public'::text, p_immediate_limit integer DEFAULT 40)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
    v_count integer;
begin
    insert into archive.github_push_queue(function_history_id)
    select function_history_id
    from archive.update_functions(p_schema)
    on conflict (function_history_id) do nothing;

    get diagnostics v_count = row_count;

    if p_immediate_limit > 0 then
      perform archive.process_github_push_queue(p_immediate_limit);
    end if;

    return v_count;
end;
$function$
