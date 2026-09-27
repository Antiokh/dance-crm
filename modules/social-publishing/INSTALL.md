# Installation contract

## Database

Apply the canonical migrations in timestamp order:

1. `supabase/migrations/20260927133000_social_command_queue.sql`
2. `supabase/migrations/20260927134000_social_publishing_core.sql`
3. consumer adapter, for Dance CRM: `supabase/migrations/20260927134500_event_social_adapter.sql`
4. `supabase/migrations/20260927141000_social_dispatch_worker.sql`
5. `supabase/migrations/20260927142000_social_admin_ops.sql`

The first migration creates the exposed durable command boundary. The second creates the non-exposed reusable `social` schema and delivery state without any Dance CRM table references. The consumer adapter owns event snapshot materialization and triggers. The last two install worker scheduling and safe admin operations.

The target Supabase API configuration must **not** expose the `social` schema. Dance CRM currently exposes only `public` and `graphql_public`.

## Edge Functions

Deploy:

- `supabase/functions/social-command-worker`
- `supabase/functions/social-publish-dispatch`

Both functions are cron/service endpoints, not browser endpoints. They authenticate with the per-environment Vault worker secret forwarded in `x-social-worker-secret`.

## Provider secrets

Set provider credentials only as Edge Function secrets. Never store them in destination settings or command payloads.

Current provider contract:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_SOCIAL_CHAT_ID`
- `TELEGRAM_SOCIAL_CHAT_USERNAME` (optional)
- `TELEGRAM_APP_BOT_USERNAME`
- `THREADS_ACCESS_TOKEN`
- `THREADS_USER_ID`
- `INSTAGRAM_ACCESS_TOKEN`
- `INSTAGRAM_USER_ID`
- `INSTAGRAM_SOCIAL_IMAGE_URL` (optional fallback)
- `MAKE_FACEBOOK_WEBHOOK_URL`
- `MAKE_SOCIAL_PUBLISHING_WEBHOOK_URL` (fallback)
- `MAKE_SOCIAL_WEBHOOK_URL` (legacy fallback)

## Environment activation

Destinations are installed disabled.

After deploying both Edge Functions, configure the current environment:

```sql
select public.admin_configure_social_workers(
  'https://<project-ref>.supabase.co/functions/v1/social-command-worker',
  'https://<project-ref>.supabase.co/functions/v1/social-publish-dispatch',
  true
);
```

Then enable only destinations whose provider credentials and settings have been verified.

Each environment owns its worker URLs and Vault secret. A preview environment therefore cannot silently dispatch into production.

## Consumer requirements

A consumer must provide an enqueue policy and adapter for its source type. Consumer code may write durable intent to the public command boundary but must not write `social.*`.

The system/service command worker is the normal privileged entry into the private social schema.
