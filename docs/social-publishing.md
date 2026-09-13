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

Recommended source fields:

- `source_type` — `event | class | course | announcement | manual`
- `source_id` — nullable UUID / external key
- `source_title`
- `source_url`
- `status`
- `metadata jsonb`

### `social_post_variants`

Platform-ready content.

One logical post can have multiple variants, for example:

- Telegram
- Instagram
- Instagram Story
- Facebook
- Threads

Each variant stores its body, link and metadata independently.

### `social_destinations`

Configured destinations / accounts.

Examples:

- `telegram_main`
- `instagram`
- `instagram_story`
- `facebook`
- `threads`
- `make_webhook`

Destination settings should determine transport configuration and optional feature flags.

### `social_publication_jobs`

Durable delivery queue with scheduling, retries, leases, external IDs and error state.

Reuse the RSLive semantics where possible:

- idempotent scheduling
- leased jobs
- retry state
- external publication ID / URL
- destination rate-limit state
- terminal / ambiguous publish protection

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

This allows event orchestration to be retried safely without duplicate announcements or duplicate polls.

## Telegram poll flow

After the Telegram announcement is published, persist the returned Telegram `message_id`.

Then call `sendPoll` using that message as the reply target.

The exact answer set is configurable. Historical behavior can be preserved, but a clearer default is:

- Буду
- Скорее буду
- Пока не знаю
- Не смогу

The poll is event-specific behavior and therefore belongs to the event orchestration layer, not the generic Telegram publisher.

## Weather-aware OpenAir policy

Use a weather provider in the event orchestration layer. Open-Meteo is a suitable default candidate because it provides hourly forecast data without requiring an API key for ordinary usage.

The decision should not be a single rain boolean. Compute a status from event-time conditions:

- precipitation probability
- precipitation / rain
- wind
- temperature
- weather code

Result:

- `good`
- `uncertain`
- `bad`

The thresholds belong in configuration rather than hard-coded scattered logic.

Recommended lifecycle:

```text
T-7d   main announcement (unless clearly unsuitable)
T-24h  weather recheck + reminder decision
T-4h   final weather check
T-1h   final Story / Telegram reminder only if confirmed
```

Exact timing will remain configurable.

## Manual publishing

The social subsystem must support posts without an event.

Minimum UI / API fields:

- title
- text
- optional link
- template / uploaded asset
- destinations
- publish now / scheduled time

This keeps the publisher useful before the full CRM UI exists.

## Make compatibility

Keep `make_webhook` as a first-class destination during migration from the old system.

The existing Make webhook contract should be documented before changing it. Secrets must live in Supabase secrets / environment variables, not in repository files or database template definitions.

## First milestone

1. Port core social tables / RPCs from RSLive.
2. Port `social-publish-dispatch` with only the destinations needed for the first test.
3. Implement poster rendering.
4. Implement manual post creation.
5. Implement event announcement sync.
6. Implement Telegram announcement + poll.
7. Add weather-aware OpenAir scheduling.
