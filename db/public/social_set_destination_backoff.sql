-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: social_set_destination_backoff
-- Updated:  2026-09-26T20:35:02.877Z

-- overload
-- language: plpgsql
-- args: p_destination_key text, p_retry_after_at timestamp with time zone, p_error text DEFAULT NULL::text
-- returns: social_destinations

CREATE OR REPLACE FUNCTION public.social_set_destination_backoff(p_destination_key text, p_retry_after_at timestamp with time zone, p_error text DEFAULT NULL::text)
 RETURNS social_destinations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$ declare v_row public.social_destinations; begin update public.social_destinations set rate_limited_at=now(),retry_after_at=p_retry_after_at,last_error=p_error where key=p_destination_key returning * into v_row; if not found then raise exception 'social destination not found' using errcode='P0002'; end if; return v_row; end; $function$
