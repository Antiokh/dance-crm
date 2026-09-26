-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_user_id
-- Updated:  2026-09-26T20:35:09.428Z

-- overload
-- language: plpgsql
-- args: apikey text
-- returns: uuid

CREATE OR REPLACE FUNCTION public.get_user_id(apikey text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
Declare  
 is_found uuid;
Begin
  SELECT user_id
  INTO is_found
  FROM apikeys
  WHERE key=apikey;
  RETURN is_found;
End;  
$function$
