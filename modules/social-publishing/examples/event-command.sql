-- Example consumer action. The caller still needs to satisfy public.social_commands RLS.
select public.enqueue_social_command(
  'social.publish',
  'event',
  '<event-uuid>'::uuid,
  'announcement',
  '{}'::jsonb,
  300
);

-- Normal Dance CRM code does not insert into social.publications or
-- social.delivery_jobs. Those are materialized by social-command-worker.
