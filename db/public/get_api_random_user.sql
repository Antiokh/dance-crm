-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_api_random_user
-- Updated:  2026-09-26T20:34:22.844Z

-- overload
-- language: plpgsql
-- args: 
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.get_api_random_user()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pgmq', 'vault'
AS $function$
DECLARE
    response jsonb;
BEGIN

   select content::json->'results'->0
   into response
   from http_get('https://randomuser.me/api/');

   return response::jsonb;

END;
$function$
