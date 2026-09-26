-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: is_allowed_apikey
-- Updated:  2026-09-26T20:35:04.197Z

-- overload
-- language: plpgsql
-- args: apikey text, permission key_permission[]
-- returns: boolean

CREATE OR REPLACE FUNCTION public.is_allowed_apikey(apikey text, permission key_permission[])
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
Begin
  RETURN (SELECT EXISTS (SELECT 1
  FROM apikeys
  WHERE key=((current_setting('request.headers'::text, true))::json ->> 'capgkey'::text)
  AND permission=ANY(permission)));
End;  
$function$
