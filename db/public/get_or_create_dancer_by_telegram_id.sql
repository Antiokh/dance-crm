-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_or_create_dancer_by_telegram_id
-- Updated:  2026-09-26T20:34:32.069Z

-- overload
-- language: plpgsql
-- args: p_telegram_id integer
-- returns: dancer

CREATE OR REPLACE FUNCTION public.get_or_create_dancer_by_telegram_id(p_telegram_id integer)
 RETURNS dancer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pgmq', 'vault'
AS $function$
DECLARE
    v_dancer public.dancer;
BEGIN
    -- Try to find an existing dancer with the given telegram_id
    SELECT *
    INTO v_dancer
    FROM public.dancer
    WHERE telegram_id = p_telegram_id;

    -- If no dancer was found, create a new one
    IF v_dancer IS NULL THEN
        INSERT INTO public.dancer (telegram_id)
        VALUES (p_telegram_id)
        RETURNING * INTO v_dancer;
    END IF;

    -- Return the found or newly created dancer record
    RETURN v_dancer;
END;
$function$
