-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: telegram_send_with_miniapp
-- Updated:  2026-09-26T20:34:52.391Z

-- overload
-- language: plpgsql
-- args: chat_id text, message_markdown text, app_path text DEFAULT ''::text
-- returns: json

CREATE OR REPLACE FUNCTION public.telegram_send_with_miniapp(chat_id text, message_markdown text, app_path text DEFAULT ''::text)
 RETURNS json
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pgmq', 'vault'
AS $function$
declare
  full_url text := 'https://1f223f7a-7bc9-4d2e-a033-89fe06e9dea2.weweb-preview.io' || app_path;
  reply_markup jsonb;
begin
  reply_markup := jsonb_build_object(
    'inline_keyboard', jsonb_build_array(
      jsonb_build_array(
        jsonb_build_object(
          'text', 'Открыть Mini App',
          'web_app', jsonb_build_object('url', full_url)
        )
      )
    )
  );

  return telegram_send_message(chat_id, message_markdown, reply_markup, 'Markdown');
end;
$function$
