-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: telegram_send_message
-- Updated:  2026-09-26T20:34:51.030Z

-- overload
-- language: plpgsql
-- args: chat_id text, message text, reply_markup jsonb DEFAULT NULL::jsonb, parse_mode text DEFAULT 'Markdown'::text
-- returns: json

CREATE OR REPLACE FUNCTION public.telegram_send_message(chat_id text, message text, reply_markup jsonb DEFAULT NULL::jsonb, parse_mode text DEFAULT 'Markdown'::text)
 RETURNS json
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pgmq', 'vault'
AS $function$
declare
  payload jsonb;
begin
  payload := jsonb_build_object(
    'chat_id', chat_id,
    'text', message,
    'parse_mode', parse_mode
  );

  if reply_markup is not null then
    payload := payload || jsonb_build_object('reply_markup', reply_markup);
  end if;

  return telegram_call('sendMessage', payload);
end;
$function$
