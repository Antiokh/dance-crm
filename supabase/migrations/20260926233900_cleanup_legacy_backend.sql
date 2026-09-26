-- DanceApp legacy cleanup after verified export.
-- Preserved: dancer/style identity data, target Dancers domain schema, event/visit schema.
-- Removed: obsolete API-key auth, legacy Telegram SQL delivery queue, empty copied social delivery subsystem.
-- The 10 public.event rows removed below are the archived prototype/seed rows created together on 2025-04-08.

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid
    from cron.job
    where jobname = 'telegram_queue_worker'
       or command ilike '%process_telegram_message%'
       or command ilike '%keepalive_telegram_message%'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
end
$$;

drop trigger if exists tg_enqueue_telegram_message on public.telegram_messages;

drop function if exists public.enqueue_telegram_message();
drop function if exists public.keepalive_telegram_message();
drop function if exists public.process_telegram_message();
drop function if exists public.queue_telegram_message();
drop function if exists public.queue_unsent_messages();
drop function if exists public.telegram_send_with_miniapp(text, text, text);
drop function if exists public.telegram_send_message(text, text, jsonb, text);
drop function if exists public.telegram_call(text, jsonb);
drop function if exists public.get_or_create_dancer_by_telegram_id(integer);
drop function if exists public.get_api_random_user();
drop function if exists public.set_dancer(uuid, text, boolean);

do $$
begin
  if exists (
    select 1
    from pgmq.list_queues()
    where queue_name = 'telegram_message_queue'
  ) then
    perform pgmq.drop_queue('telegram_message_queue');
  end if;
end
$$;

drop table if exists public.telegram_messages;

drop function if exists public.social_claim_publication_jobs(text, integer, integer, integer);
drop function if exists public.social_mark_publication_failed(uuid, text, text, integer, boolean, jsonb);
drop function if exists public.social_mark_publication_succeeded(uuid, text, text, text, jsonb);
drop function if exists public.social_schedule_variant(uuid, text, timestamptz, text, integer, timestamptz, uuid, integer, jsonb);
drop function if exists public.social_set_destination_backoff(text, timestamptz, text);

drop table if exists public.social_publication_jobs;
drop table if exists public.social_post_variants;
drop table if exists public.social_posts;
drop table if exists public.social_destinations;
drop function if exists public.social_touch_updated_at();

-- The target Dancers architecture no longer uses the legacy API-key authorization model.
-- This extension owns public.apikeys, key_permission and its helper RPCs.
drop extension if exists "martindonadieu@supabase_auth_apikey" cascade;

-- The archived rows are generic prototype fixtures, not confirmed operational events.
delete from public.event;

-- event/visit remain as a closed irregular-event domain for the later Phase 9 redesign.
revoke all on public.event from anon, authenticated;
revoke all on public.visit from anon, authenticated;
