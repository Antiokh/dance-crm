# Event announcements, weather and RSVP

Implementation issue: #32.

## Event templates

Administrators can save the stable parts of an event as an `event_templates` row:

- type;
- title and description;
- announcement image;
- duration;
- venue;
- dance style.

Selecting a template fills those fields. The administrator normally changes only the start date/time. A stored duration recalculates the end time.

## Weather

The event editor calls the authenticated `event-weather` Edge Function when it has:

- a start date/time;
- a venue;
- venue latitude/longitude.

The browser never receives the OpenWeather key. Configure this Edge secret:

```text
OPENWEATHER_API_KEY
```

The implementation uses OpenWeather's 5 day / 3 hour forecast endpoint and picks the forecast point nearest the event start. Events outside the provider horizon show “forecast will appear closer to the event” instead of failing the editor.

## RSVP contract

Event RSVP has three user-visible states:

- no response;
- `going`;
- `not_going`.

`event_attendance.role_id` stores the Leader/Follower snapshot at the moment a dancer answers `going`. Profile changes later do not rewrite historical event balance.

The legacy quick-attend switch keeps its old meaning:

- on → `going`;
- off → no response.

The explicit social CTA uses `set_my_event_response()` and can therefore store `not_going`.

Telegram Mini App start parameters:

```text
event_<event-uuid>_going
event_<event-uuid>_not_going
```

They remain below Telegram's start parameter size limit for UUID event IDs.

## Social delivery

The CRM remains in the exposed `public` schema and continues to rely on RLS. Social publishing is different: its implementation state lives in a non-exposed `social` schema because workers operate with system/service privileges and provider/reconciliation state must never become part of the Data API surface.

Domain changes only enqueue durable intent:

```text
public.dance_events / public.event_attendance
  -> public.social_commands
  -> social-command-worker
  -> social.publications
  -> social.delivery_jobs
  -> social-publish-dispatch
```

`public.social_commands` is the security boundary. The public enqueue function is `SECURITY INVOKER`; browser/domain code never writes `social.*` directly. The command worker is the privileged system boundary that materializes private publications and delivery jobs.

The private publication table references CRM sources generically with `source_type`, `source_id`, and an operation/version snapshot. It has no foreign key to `dance_events`, so the publisher can later be extracted as a reusable module.

Publishers:

- Telegram → Bot API;
- Threads → Threads API;
- Instagram → Instagram Graph API;
- Facebook → Make webhook, matching the RSLive/Dobri integration boundary.

RSVP changes create coalesced Telegram `edit` jobs. The worker edits the latest published Telegram announcement and renders the current Leader/Follower balance plus the current list of dancers who are going.

Destinations are created disabled. Enable them only after the corresponding credentials and destination settings are verified.

## Required Edge Function secrets

Configure only the providers that will be enabled:

```text
# Telegram
TELEGRAM_BOT_TOKEN
TELEGRAM_SOCIAL_CHAT_ID
TELEGRAM_SOCIAL_CHAT_USERNAME      # optional; used to persist a t.me post URL
TELEGRAM_APP_BOT_USERNAME         # Mini App bot used by RSVP startapp links

# Threads
THREADS_ACCESS_TOKEN
THREADS_USER_ID

# Instagram
INSTAGRAM_ACCESS_TOKEN
INSTAGRAM_USER_ID
INSTAGRAM_SOCIAL_IMAGE_URL         # optional fallback

# Facebook / Make
MAKE_FACEBOOK_WEBHOOK_URL          # destination-specific, preferred when present
MAKE_SOCIAL_PUBLISHING_WEBHOOK_URL # generic fallback
MAKE_SOCIAL_WEBHOOK_URL            # legacy fallback
```

Provider tokens and webhook secrets must stay in Edge Function secrets. Do not put them in `social_destinations.settings`.

Instagram feed posts require a public image URL. `announcement_image_url` is therefore part of both an event and its reusable template. `INSTAGRAM_SOCIAL_IMAGE_URL` is only a fallback.

## Destination configuration

Safe non-secret settings can be updated through:

```sql
select public.admin_set_social_destination(
  'telegram',
  true,
  jsonb_build_object(
    'chat_id', '<telegram chat id>',
    'chat_username', '<public channel username>',
    'bot_username', '<mini app bot username>'
  )
);

select public.admin_set_social_destination(
  'threads',
  true,
  '{}'::jsonb
);

select public.admin_set_social_destination(
  'instagram',
  true,
  '{}'::jsonb
);

select public.admin_set_social_destination(
  'facebook',
  true,
  '{}'::jsonb
);
```

The RPC rejects common secret fields such as tokens, passwords and webhook URLs.

## Worker scheduling

The migration creates one per-environment random worker secret in Supabase Vault and installs two once-per-minute cron jobs:

1. `social-command-worker` claims `public.social_commands` and materializes private publisher state;
2. `social-publish-dispatch` claims `social.delivery_jobs` through service-only RPCs and talks to providers.

Both crons are deliberately inert until that environment's own Edge Function URLs are configured. This prevents a preview/branch database from accidentally calling production.

After deploying both functions, configure:

```sql
select public.admin_configure_social_workers(
  'https://<project-ref>.supabase.co/functions/v1/social-command-worker',
  'https://<project-ref>.supabase.co/functions/v1/social-publish-dispatch',
  true
);
```

The database sends the Vault-managed worker secret as `x-social-worker-secret`. Both functions compare it in constant time before claiming work.

## Delivery safety

The two-stage queue provides:

- an RLS-protected public command boundary separated from the private delivery queue;
- idempotency keys;
- leases and lease expiry recovery;
- retry/dead states;
- destination and shared provider rate gates;
- at most one claimed job per shared rate gate in each batch;
- persisted external post IDs/URLs;
- ambiguous-publish protection for non-idempotent provider finalization;
- coalescing of superseded RSVP edits;
- browser roles with no direct access to queue tables.

Telegram message edits are safe to retry. New Telegram posts, Threads final publish, Instagram final publish and Make calls are treated as ambiguous after the provider request starts; a worker crash does not blindly duplicate them.

## Diagnostics

Administrators can inspect worker configuration, command state, destination state and the latest private publication jobs with:

```sql
select public.admin_get_social_delivery_status(null);
select public.admin_get_social_delivery_status('<event-uuid>');
```

The worker also writes best-effort events to `debug_events` with source `social-publish-dispatch`.
