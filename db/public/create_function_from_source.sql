-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: create_function_from_source
-- Updated:  2026-09-26T20:34:48.437Z

-- overload
-- language: plpgsql
-- args: function_text text, schema_name text DEFAULT 'public'::text
-- returns: text

CREATE OR REPLACE FUNCTION public.create_function_from_source(function_text text, schema_name text DEFAULT 'public'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  function_name text;
  argument_types text;
  return_type text;
  function_source text;
  lang_settings text;
BEGIN
  -- Execute the function text to create the function
  EXECUTE function_text;

  -- Extract function name from function text
  SELECT (regexp_matches(function_text, 'create (or replace )?function (public\.)?(\w+)', 'i'))[3]
  INTO function_name;

  -- Get function details from the system catalog
  SELECT pg_get_function_result(p.oid), 
                pg_get_function_arguments(p.oid), p.prosrc, l.lanname
  INTO return_type, argument_types, function_source, lang_settings
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_language l ON l.oid = p.prolang
  WHERE n.nspname = schema_name AND p.proname = function_name;

  -- Save function history
  PERFORM archive.save_function_history(function_name, argument_types, return_type, function_text, schema_name, lang_settings);

  RETURN 'Function created successfully.';
EXCEPTION
  WHEN others THEN
    RAISE EXCEPTION 'Error creating function: %', sqlerrm;
END;
$function$
