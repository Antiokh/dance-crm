# Supabase

This project is migration-first.

## Source of truth

Runtime database changes must be committed as timestamped files under:

`supabase/migrations/`

Do not make persistent production schema changes in the Dashboard without pulling
them back into a migration immediately.

Generated SQL function snapshots under `db/` are audit artifacts and are not
hand-edited source.

## GitHub Integration

Supabase Project Settings -> Integrations -> GitHub:

- Repository: `Antiokh/dance-crm`
- Working directory: `.`
- Production branch: `main`
- Deploy to production: enabled
- Automatic branching: enable if preview branches are desired
- Supabase changes only: recommended

Supabase applies only migrations not yet present in the target branch migration
history. Edge Functions declared in `config.toml` are deployed from Git.

## Function versioning

The first infrastructure migration installs:

- `archive.function_history`
- change detection helpers
- durable Git publication queue
- recovery helpers
- service-only publication payload RPC

`github-send` writes generated snapshots to:

`db/<schema>/<function_name>.sql`

Cron is intentionally installed in a later migration after the manual publication
path has been verified on production.
