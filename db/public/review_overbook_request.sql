-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: review_overbook_request
-- Updated:  2026-09-27T01:12:00.829Z

-- overload
-- language: sql
-- args: p_request_id uuid, p_approve boolean, p_note text DEFAULT NULL::text
-- returns: overbook_requests

CREATE OR REPLACE FUNCTION public.review_overbook_request(p_request_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS overbook_requests
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.review_overbook_request_internal(
    p_request_id,
    p_approve,
    p_note
  )
$function$
