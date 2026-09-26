-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: calculate_version
-- Updated:  2026-09-26T20:34:47.018Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION public.calculate_version()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Calculate the version number for new rows
    SELECT COALESCE(MAX(version), 0) + 1
    INTO NEW.version
    FROM archive.function_history
    WHERE schema_name = NEW.schema_name
      AND function_name = NEW.function_name
      AND return_type = NEW.return_type
      AND args = NEW.args;

  RETURN NEW;
END;
$function$
