-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: create_apikey
-- Updated:  2026-09-26T20:35:05.515Z

-- overload
-- language: plpgsql
-- args: permission, key_permission
-- returns: apikeys

CREATE OR REPLACE FUNCTION public.create_apikey(permission, key_permission)
 RETURNS apikeys
 LANGUAGE plpgsql
AS $function$
DECLARE
	new_apikey "public"."apikeys";
BEGIN
return create_apikey(auth.uid(), permission);
END;
$function$

-- overload
-- language: plpgsql
-- args: user_id uuid, permission key_permission
-- returns: apikeys

CREATE OR REPLACE FUNCTION public.create_apikey(user_id uuid, permission key_permission)
 RETURNS apikeys
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
	new_apikey "public"."apikeys";
BEGIN
	new_apikey := (INSERT INTO apikeys (user_id, permission, key)
		VALUES (user_id, permission, md5(random()::text || clock_timestamp()::text)::uuid)
		RETURNING *);
	RETURN new_apikey;
END;
$function$
