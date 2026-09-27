# Installation contract

## Database

The reusable core is:

1. `supabase/migrations/20260927133000_social_command_queue.sql` — durable command table and service worker lease/retry primitives;
2. `supabase/migrations/20260927134000_social_publishing_core.sql` — non-exposed `social` schema, destinations, publications, delivery queue and service-only delivery RPCs;
3. `supabase/migrations/20260927141000_social_dispatch_worker.sql` — Vault/cron worker infrastructure and service-only worker configuration.

Dance CRM then adds consumer-specific migrations:

4. `supabase/migrations/20260927134500_event_social_adapter.sql` — authenticated enqueue policy/API, event snapshots, triggers and command processor;
5. `supabase/migrations/20260927142000_social_admin_ops.sql` — Dance administrator wrappers and diagnostics.

The reusable core contains no Dance CRM domain-table or app-role dependency. A different consumer supplies its own enqueue policy and `social_process_command` adapter.

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
select public.social_configure_workers(
  'https://<project-ref>.supabase.co/functions/v1/social-command-worker',
  'https://<project-ref>.supabase.co/functions/v1/social-publish-dispatch',
  true,
  null
);
```

The reusable configuration RPC is executable only by `service_role`. Dance CRM also exposes an administrator wrapper, `admin_configure_social_workers(...)`, which performs the app-role check and calls this service boundary.

Then enable only destinations whose provider credentials and settings have been verified.

Each environment owns its worker URLs and Vault secret. A preview environment therefore cannot silently dispatch into production.

## Consumer requirements

A consumer must provide an enqueue policy and adapter for its source type. Consumer code may write durable intent to the public command boundary but must not write `social.*`.

The system/service command worker is the normal privileged entry into the private social schema.
