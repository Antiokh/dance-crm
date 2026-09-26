-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: update_function_history
-- Updated:  2026-09-26T22:01:16.428Z

-- overload
-- language: plpgsql
-- args: function_name text, args text, return_type text, source_code text, schema_name text DEFAULT 'public'::text, lang_settings text DEFAULT 'plpgsql'::text
-- returns: boolean

CREATE OR REPLACE FUNCTION archive.update_function_history(function_name text, args text, return_type text, source_code text, schema_name text DEFAULT 'public'::text, lang_settings text DEFAULT 'plpgsql'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
declare
  v_prev_id bigint;
  v_prev_code text;
  v_prev_active boolean;
begin
  select fh.id, fh.source_code, fh.active
  into v_prev_id, v_prev_code, v_prev_active
  from archive.function_history fh
  where fh.schema_name = update_function_history.schema_name
    and fh.function_name = update_function_history.function_name
    and fh.args = update_function_history.args
    and fh.return_type = update_function_history.return_type
    and fh.lang_settings = update_function_history.lang_settings
  order by fh.id desc
  limit 1;

  if v_prev_code is not null and not exists (
    select 1 from archive.diff_text(v_prev_code, source_code)
  ) then
    if not v_prev_active then
      update archive.function_history fh
      set active = false
      where fh.schema_name = update_function_history.schema_name
        and fh.function_name = update_function_history.function_name
        and fh.args = update_function_history.args
        and fh.return_type = update_function_history.return_type
        and fh.lang_settings = update_function_history.lang_settings;

      update archive.function_history
      set active = true
      where id = v_prev_id;
    end if;

    return false;
  end if;

  update archive.function_history fh
  set active = false
  where fh.schema_name = update_function_history.schema_name
    and fh.function_name = update_function_history.function_name
    and fh.args = update_function_history.args
    and fh.return_type = update_function_history.return_type
    and fh.lang_settings = update_function_history.lang_settings;

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

  return true;
end;
$function$
