-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: setup_function_history
-- Updated:  2026-09-26T20:33:29.106Z

-- overload
-- language: plpgsql
-- args: schema_name text DEFAULT 'public'::text
-- returns: void

CREATE OR REPLACE FUNCTION archive.setup_function_history(schema_name text DEFAULT 'public'::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
    function_record record;
begin
    update archive.function_history fh
    set active = false
    where fh.schema_name = setup_function_history.schema_name;

    for function_record in (
        select
            n.nspname as schema_name,
            p.proname as function_name,
            pg_catalog.pg_get_function_arguments(p.oid) as args,
            pg_catalog.pg_get_function_result(p.oid) as return_type,
            pg_catalog.pg_get_functiondef(p.oid) as source_code,
            l.lanname as lang_settings
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        join pg_catalog.pg_language l on l.oid = p.prolang
        where n.nspname = setup_function_history.schema_name
          and p.prokind = 'f'
    )
    loop
        perform archive.save_function_history(
            function_record.function_name,
            function_record.args,
            function_record.return_type,
            function_record.source_code,
            function_record.schema_name,
            function_record.lang_settings
        );
    end loop;
end;
$function$
