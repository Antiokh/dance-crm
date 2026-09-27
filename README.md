# Dance CRM backend

This repository is the backend source of truth for the Supabase project **DanceApp**.

The product/application architecture lives in `Antiokh/dancers`. The backend here implements that architecture and uses `Antiokh/supabase-project-starter` as the infrastructure baseline.

## Source-of-truth rules

- Persistent database changes: `supabase/migrations/`.
- Edge Functions: `supabase/functions/`.
- Generated live-database artifacts: `db/**` — audit/sync output, never hand-edit.
- Product/domain architecture: `Antiokh/dancers/docs/**`.
- TMA interaction patterns: `Antiokh/dobri-visarun`.

The live database remains authoritative for generated function/table snapshots. Git migrations and Edge Function sources are authoritative for intentional backend changes.

## Infrastructure layers

DanceApp uses separate infrastructure layers:

1. SQL function history in `archive.function_history`.
2. Table DDL history in `archive.table_history`.
3. Durable Git publication queue with retry/dead recovery.
4. Tokenized `github-send` Edge publication boundary.
5. Scheduled change scan and bounded queue drain.
6. Whole-schema JSON snapshot/export, separate from function/table history.
7. Shared Edge runtime helpers and service-only debug logging.
8. Telegram Mini App authentication based on the Dobri Visarun flow.

Schema export and generated DB commits must not be treated as migration source.


## Feature notes

- Event templates, weather, social publication and RSVP delivery: `docs/EVENT_ANNOUNCEMENTS.md`.

## Legacy baseline

DanceApp predates this repository. Historical migrations before the Dancers rebuild do not reconstruct the original legacy schema from an empty database.

The preserved pre-cleanup archive is in the private `Antiokh/dancers` repository under:

`supabase/legacy-export/2026-09-26/`

Do not restore that archive wholesale. It is evidence/recovery material; migrations in this repository define the forward backend.
