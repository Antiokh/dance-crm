-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: telegram_send_message_debug
-- Updated:  2026-09-26T20:35:44.673Z

-- overload
-- language: plpgsql
-- args: chat_id text, message text, reply_markup jsonb DEFAULT NULL::jsonb, parse_mode text DEFAULT 'MarkdownV2'::text
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.telegram_send_message_debug(chat_id text, message text, reply_markup jsonb DEFAULT NULL::jsonb, parse_mode text DEFAULT 'MarkdownV2'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  payload jsonb;
  final_text text;
  response json;
begin
  if parse_mode = 'MarkdownV2' then
    final_text := escape_markdown_v2(message);
  else
    final_text := message;
  end if;

  payload := jsonb_build_object(
    'chat_id', chat_id,
    'text', final_text,
    'parse_mode', parse_mode
  );

  if reply_markup is not null then
    payload := payload || jsonb_build_object('reply_markup', reply_markup);
  end if;

  response := telegram_call('sendMessage', payload);

  return jsonb_build_object(
    'sent_payload', payload,
    'telegram_response', response
  );
end;
$function$
