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

Publishing or materially updating a published event creates an immutable event publication and durable jobs:

```text
dance_events
  -> event_social_publications
  -> social_publication_jobs
  -> social-publish-dispatch
```

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

The migration creates a per-environment random worker secret in Supabase Vault and installs a once-per-minute cron job.

The cron is deliberately inert until that environment's own Edge Function URL is configured. This prevents a preview/branch database from accidentally calling production.

After deploying `social-publish-dispatch`, configure:

```sql
select public.admin_configure_social_dispatch(
  'https://<project-ref>.supabase.co/functions/v1/social-publish-dispatch',
  true
);
```

The database sends the Vault secret as `x-dance-social-secret`. The function compares it in constant time before claiming any jobs.

## Delivery safety

The queue provides:

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

Administrators can inspect destination state, dispatch configuration and the latest publication jobs with:

```sql
select public.admin_get_social_delivery_status(null);
select public.admin_get_social_delivery_status('<event-uuid>');
```

The worker also writes best-effort events to `debug_events` with source `social-publish-dispatch`.
