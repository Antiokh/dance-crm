# Social publishing module

This directory documents the reusable social-publishing boundary implemented by Dance CRM.

The canonical runtime files remain under `supabase/migrations` and `supabase/functions` so there is only one executable source of truth. This directory is the extraction contract for moving the module into `Antiokh/supabase-project-starter` later.

## Boundary

The module has two queues with different responsibilities:

```text
consumer/domain
  -> public enqueue API
  -> durable command queue
  -> system command worker
  -> social.* private state
  -> delivery queue
  -> delivery dispatcher
  -> providers
```

The consumer owns domain state. The social module never owns events, bookings, dancers, or attendance.

The reusable private state references a source only by:

- `source_type`;
- `source_id`;
- operation/publication kind;
- immutable payload snapshot.

There are no foreign keys from `social.*` to Dance CRM domain tables.

## Reusable core

- non-exposed `social` schema;
- destinations and safe non-secret settings;
- immutable publications;
- delivery jobs;
- provider/shared rate gates;
- scheduling via `available_at`;
- transactional/scheduled lanes;
- expiration;
- dependencies;
- priority aging / anti-starvation;
- leases and retries;
- idempotency;
- ambiguous provider-response protection;
- worker configuration;
- command and delivery worker authentication;
- Telegram, Threads, Instagram and Make transports.

## Consumer adapter

Dance CRM supplies the event-specific adapter:

- event/attendance triggers that enqueue commands;
- event snapshot construction;
- RSVP balance and attendee rendering context;
- Telegram event CTA URLs;
- admin event publication action.

A future consumer can replace those pieces without changing private queue/delivery state.

## Canonical files

See `INSTALL.md` for the exact installation order and `API.md` for the exposed/service-only contract.
