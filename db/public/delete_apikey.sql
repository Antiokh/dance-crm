-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: delete_apikey
-- Updated:  2026-09-26T20:35:08.188Z

-- overload
-- language: plpgsql
-- args: apikey text
-- returns: boolean

CREATE OR REPLACE FUNCTION public.delete_apikey(apikey text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
	DELETE FROM apikeys WHERE key=apikey;
	RETURN true;
END;
$function$
