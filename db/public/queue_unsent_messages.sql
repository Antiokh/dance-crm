-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: queue_unsent_messages
-- Updated:  2026-09-26T20:34:53.676Z

-- overload
-- language: plpgsql
-- args: 
-- returns: void

CREATE OR REPLACE FUNCTION public.queue_unsent_messages()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pgmq', 'vault'
AS $function$
declare
  rec record;
begin
  for rec in
    select * from telegram_messages where is_sent = false
  loop
    perform pgmq.send(
      'telegram_message_queue',
      jsonb_build_object(
        'id', rec.id,
        'chat_id', rec.chat_id,
        'message_markdown', rec.message_markdown,
        'app_path', rec.app_path
      )
    );
    update telegram_messages set is_sent = true where id = rec.id;
  end loop;
end;
$function$
