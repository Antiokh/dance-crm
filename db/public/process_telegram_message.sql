-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: process_telegram_message
-- Updated:  2026-09-26T20:35:00.098Z

-- overload
-- language: plpgsql
-- args: 
-- returns: void

CREATE OR REPLACE FUNCTION public.process_telegram_message()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pgmq', 'vault'
AS $function$
DECLARE
  m_record RECORD;
  msg jsonb;
  result json;
BEGIN
  -- Получаем одно сообщение из очереди
  SELECT * INTO m_record
  FROM pgmq.pop('telegram_message_queue')
  LIMIT 1;

  IF m_record.message IS NULL THEN
    RETURN;
  END IF;

  msg := m_record.message;

  -- Отправляем сообщение через Telegram
  result := telegram_send_with_miniapp(
    msg->>'chat_id',
    msg->>'message_markdown',
    msg->>'app_path'
  );

  -- Обновляем лог отправки
  UPDATE telegram_messages
  SET
    telegram_response = result,
    telegram_message_id = (result->'result'->>'message_id')::bigint,
    sent_at = now()
  WHERE id = (msg->>'id')::uuid;

  -- Удаляем сообщение из очереди
  PERFORM pgmq.delete('telegram_message_queue', ARRAY[m_record.msg_id]);
END;
$function$
