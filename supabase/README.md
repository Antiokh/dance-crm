# Supabase / DanceApp

Remote project: `DanceApp` (`acmgtkethcijxgldrfgw`).

This repository is migration-first and is the backend source of truth for that project.

## Persistent changes

All intentional database changes are timestamped files under:

`supabase/migrations/`

Do not hand-edit generated `db/**` snapshots. They are published from the live database by the versioning/export infrastructure.

## Current infrastructure

- function history: `archive.function_history`;
- table history: `archive.table_history`;
- durable publication queue: `archive.github_push_queue`;
- queue recovery helpers and bounded cron processing;
- tokenized `github-send` Edge Function;
- whole-schema snapshots: `archive.schema_export_snapshots`;
- service-only `public.debug_events`;
- Telegram auth Edge Function and shared initData validator.

Function/table history and whole-schema export are intentionally separate workflows.

## Security boundary

- browser code never receives service-role credentials;
- `github-send` has `verify_jwt=false` only because every publication request is authorized by a one-time DB-issued token and payload RPC;
- schema export cannot choose an arbitrary Git path;
- operational archive/debug objects are revoked from `anon` and `authenticated`;
- Telegram launch data is validated server-side before a Supabase Auth session is established.

## Historical baseline

The live project predates Git migration history. The pre-cleanup archive is preserved in private `Antiokh/dancers/supabase/legacy-export/2026-09-26/`.

A clean empty-project bootstrap needs an explicit baseline/squash step; do not assume the historical migration chain alone reconstructs the original database.
