-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: send_telegram_message
-- Updated:  2026-09-26T20:35:43.487Z

-- overload
-- language: plpgsql
-- args: chat_id text, message text
-- returns: json

CREATE OR REPLACE FUNCTION public.send_telegram_message(chat_id text, message text)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
declare
  url text := 'https://api.telegram.org/bot<REDACTED_LEGACY_TELEGRAM_BOT_TOKEN>/sendMessage';
  payload jsonb;
begin
  payload := jsonb_build_object(
    'chat_id', chat_id,
    'text', message
  );

  return (
    select content::json
    from http((
      'POST',
      url,
      ARRAY[
        http_header('Content-Type', 'application/json')
      ],
      'application/json',
      payload::text
    )::http_request)
  );
end;
$function$
