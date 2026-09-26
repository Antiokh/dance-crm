# Supabase GitHub Integration

The repository uses Supabase GitHub Integration as the deployment path.

## Required project settings

Set these in Supabase Dashboard -> Project Settings -> Integrations -> GitHub:

1. repository: `Antiokh/dance-crm`
2. working directory: `.`
3. production Git branch: `main`
4. Deploy to production: ON
5. Automatic branching: ON when PR preview databases are wanted
6. Supabase changes only: ON unless every branch should create a preview

The repository root contains `supabase/`, so the working directory is a single
dot, not `supabase`.

## Development rule

All persistent database changes are migrations:

`supabase/migrations/<timestamp>_<description>.sql`

Do not rewrite an already-applied migration. Add a new migration.

For PRs, Supabase builds the preview database from committed migrations. Preview
branches do not inherit production data.

## Required GitHub protection

After the first Supabase check appears on a PR, mark that check as required in
GitHub branch protection/rulesets for `main`. This prevents merging migrations
that fail in Supabase.

## Secrets

Do not commit plaintext secrets.

The `github-send` Edge Function requires `GITHUB_TOKEN`. It defaults to:

- owner: `Antiokh`
- repo: `dance-crm`
- branch: `main`

Override with `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_BRANCH` only when needed.

## Function publication

The initial versioning migration intentionally does not create a cron job.
Sequence:

1. migration passes Supabase integration
2. `github-send` deploys
3. bootstrap function history manually
4. publish one queue item
5. verify generated `db/.../*.sql`
6. add cron in a separate migration
