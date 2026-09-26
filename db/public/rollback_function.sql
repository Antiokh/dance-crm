-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: rollback_function
-- Updated:  2026-09-26T20:35:13.024Z

-- overload
-- language: plpgsql
-- args: func_name text, version_no integer DEFAULT 0, schema_n text DEFAULT 'public'::text
-- returns: text

CREATE OR REPLACE FUNCTION public.rollback_function(func_name text, version_no integer DEFAULT 0, schema_n text DEFAULT 'public'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  function_text text;
  target_version integer;
BEGIN
  -- Set the target version
  IF version_no = 0
  THEN
    SELECT version into target_version
      FROM archive.function_history
      WHERE function_name = func_name AND schema_name = schema_n
      ORDER BY updated_at DESC
  LIMIT 1;
  ELSE
    target_version := version_no;
  END IF;

  -- Get the function source of target version from the function_history table
  SELECT source_code
  INTO function_text
  FROM archive.function_history
  WHERE function_name = func_name AND schema_name = schema_n
    AND version = target_version
  ORDER BY updated_at DESC
  LIMIT 1;

  -- If no previous version is found, raise an error
  IF function_text IS NULL THEN
    RAISE EXCEPTION 'No previous version of function % found.', func_name;
  END IF;

  -- Add 'or replace' to the function text if it's not already there (case-insensitive search and replace)
  IF NOT function_text ~* 'or replace' THEN
    function_text := regexp_replace(function_text, 'create function', 'create or replace function', 'i');
  END IF;

  -- Drop current version:
  EXECUTE format('DROP FUNCTION IF EXISTS %I.%I', schema_n, func_name);
  -- Execute the function text to create the function
  EXECUTE function_text;

  RETURN 'Function rolled back successfully.';
EXCEPTION
  WHEN others THEN
    RAISE EXCEPTION 'Error rolling back function: %', sqlerrm;
END;
$function$
