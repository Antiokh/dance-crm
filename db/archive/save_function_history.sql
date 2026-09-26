-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: save_function_history
-- Updated:  2026-09-26T20:33:27.924Z

-- overload
-- language: plpgsql
-- args: function_name text, args text, return_type text, source_code text, schema_name text DEFAULT 'public'::text, lang_settings text DEFAULT 'plpgsql'::text
-- returns: void

CREATE OR REPLACE FUNCTION archive.save_function_history(function_name text, args text, return_type text, source_code text, schema_name text DEFAULT 'public'::text, lang_settings text DEFAULT 'plpgsql'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'archive'
AS $function$
declare
    v_prev_id bigint;
    v_prev_code text;
begin
    select fh.id, fh.source_code
    into v_prev_id, v_prev_code
    from archive.function_history fh
    where fh.schema_name = save_function_history.schema_name
      and fh.function_name = save_function_history.function_name
      and fh.args = save_function_history.args
      and fh.return_type = save_function_history.return_type
      and fh.lang_settings = save_function_history.lang_settings
    order by fh.id desc
    limit 1;

    if v_prev_code is not null then
        if not exists (
            select 1
            from archive.diff_text(v_prev_code, source_code)
        ) then
            update archive.function_history fh
            set active = false
            where fh.schema_name = save_function_history.schema_name
              and fh.function_name = save_function_history.function_name
              and fh.args = save_function_history.args
              and fh.return_type = save_function_history.return_type
              and fh.lang_settings = save_function_history.lang_settings;

            update archive.function_history fh
            set active = true
            where fh.id = v_prev_id;

            return;
        end if;
    end if;

    update archive.function_history fh
    set active = false
    where fh.schema_name = save_function_history.schema_name
      and fh.function_name = save_function_history.function_name
      and fh.args = save_function_history.args
      and fh.return_type = save_function_history.return_type
      and fh.lang_settings = save_function_history.lang_settings;

    insert into archive.function_history (
        schema_name,
        function_name,
        args,
        return_type,
        source_code,
        lang_settings,
        active
    )
    values (
        schema_name,
        function_name,
        args,
        return_type,
        source_code,
        lang_settings,
        true
    );
end;
$function$
