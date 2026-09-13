# Social publishing

## Goal

Provide a generic publishing service inside the DanceApp Supabase project.

The first useful scenario is:

```text
Create OpenAir event
→ render square + Story posters
→ create platform variants
→ publish announcement
→ post Telegram poll as a reply
```

The same subsystem must also support a completely manual post with no event attached.

## Core data model

The RSLive model is the reference implementation.

### `social_posts`

Logical publication independent of transport.

Source fields:

- `source_type` — `event | class | course | announcement | manual`
- `source_id` — nullable UUID / external key
- `source_title`
- `source_url`
- `status`
- `metadata jsonb`

### `social_post_variants`

Platform-ready content. One logical post can have multiple variants, for example Telegram, Instagram, Instagram Story, Facebook and Threads.

### `social_destinations`

Configured destinations / accounts. Examples: `telegram_main`, `instagram`, `instagram_story`, `facebook`, `threads`, `make_webhook`.

Provider credentials are referenced by secret name from destination settings and must live in Supabase secrets, never in the repository or ordinary database rows.

### `social_publication_jobs`

Durable delivery queue with scheduling, retries, leases, external IDs and error state.

Implemented queue fields include:

- `queue_class` — `scheduled | transactional`
- `priority` — higher values are claimed first inside a lane
- `scheduled_at` — earliest planned send time
- `available_at` — retry/backoff gate
- `expires_at` — optional hard deadline after which the message is cancelled
- `depends_on_job_id` — optional dependency that must be published first
- lease state, attempt counters and provider response

## Delivery lanes

There is one durable queue and two delivery lanes rather than two unrelated queue implementations.

`transactional` is for messages that should be delivered at the first available opportunity: booking confirmations, cancellations, urgent schedule changes, Telegram polls after an announcement, and similar operational messages.

`scheduled` is for ordinary content: announcements, Stories, reminders and regular event promotion.

The claim worker processes transactional work first. To prevent ordinary content from being starved forever, each destination tracks `transactional_streak`. If a scheduled job is ready, at most four consecutive transactional jobs may be claimed for that destination before one scheduled job is allowed through. A scheduled claim resets the streak.

Default worker batch budget is 8 transactional and 2 scheduled jobs. These are worker parameters, not schema constants.

A destination can have only one active lease at a time. Provider rate limits and `retry_after_at` are respected by the claim function.

## Job dependencies

`depends_on_job_id` models simple publication chains without embedding orchestration into transports.

Example:

```text
Telegram announcement job
        ↓ published
Telegram poll job
```

The dependent job stays queued until its dependency reaches `published`.

## Expiration

Transactional messages often have a limited useful lifetime. `expires_at` is therefore part of the queue contract.

Examples:

- urgent class cancellation — short lifetime
- booking confirmation — hours
- event reminder — must expire when the event is no longer relevant

Expired queued/retry jobs are cancelled rather than retried later.

## Event publication state

Event-specific workflow state should not be squeezed into the generic social tables.

Suggested table:

```text
event_social_state
------------------
event_id
weather_checked_at
weather_status
weather_payload jsonb
announcement_social_post_id
telegram_message_id
telegram_poll_message_id
poster_square_asset_id
poster_story_asset_id
created_at
updated_at
```

## Telegram poll flow

After the Telegram announcement is published, persist the returned Telegram `message_id`. The poll is then represented as a transactional publication job dependent on the announcement job.

The dispatcher already supports `sendMessage` and `sendPoll`; reply binding will be completed in event orchestration once the exact Telegram chat/topic setup is known.

## Weather-aware OpenAir policy

Use a weather provider in the event orchestration layer. Open-Meteo is the default candidate.

Compute `good | uncertain | bad` from event-time precipitation probability, rain, wind, temperature and weather code. Thresholds belong in configuration.

Recommended lifecycle:

```text
T-7d   main announcement
T-24h  weather recheck + reminder decision
T-4h   final weather check
T-1h   final Story / Telegram reminder only if confirmed
```

## Manual publishing

The social subsystem must support posts without an event. Minimum UI/API fields: title, text, optional link, template/uploaded asset, destinations, publish now/scheduled time.

## Make compatibility

`make_webhook` remains a first-class destination during migration. The dispatcher reads its webhook URL from a Supabase secret named by the destination configuration.

## Implementation status

Implemented in DanceApp database:

1. `social_posts`
2. `social_post_variants`
3. `social_destinations`
4. `social_publication_jobs`
5. idempotent scheduling RPC
6. transactional/scheduled claim RPC with anti-starvation policy
7. success/failure RPCs
8. destination backoff support
9. job dependencies and expiration
10. backend-only RLS posture

Implemented in repository:

- `supabase/functions/social-publish-dispatch/index.ts`
- Make webhook transport
- Telegram `sendMessage` transport
- Telegram `sendPoll` transport

Next: configure destinations/secrets, deploy and smoke-test the dispatcher, then implement image rendering and event orchestration.
