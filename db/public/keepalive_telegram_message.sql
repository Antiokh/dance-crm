-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: keepalive_telegram_message
-- Updated:  2026-09-26T20:34:26.795Z

-- overload
-- language: plpgsql
-- args: 
-- returns: void

CREATE OR REPLACE FUNCTION public.keepalive_telegram_message()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pgmq', 'vault'
AS $function$
begin
    insert into telegram_messages (chat_id, message_markdown)
    values (268170503, 'keep-alive message');
end;
$function$
