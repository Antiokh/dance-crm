-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: enqueue_telegram_message
-- Updated:  2026-09-26T20:34:55.071Z

-- overload
-- language: plpgsql
-- args: 
-- returns: trigger

CREATE OR REPLACE FUNCTION public.enqueue_telegram_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pgmq', 'vault'
AS $function$
begin
  perform pgmq.send(
    'telegram_message_queue',
    jsonb_build_object(
      'id', NEW.id,
      'chat_id', NEW.chat_id,
      'message_markdown', NEW.message_markdown,
      'app_path', NEW.app_path
    )
  );

  update telegram_messages
  set is_sent = true
  where id = NEW.id;

  return NEW;
end;
$function$
