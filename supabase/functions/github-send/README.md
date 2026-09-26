# github-send

Internal publication boundary for generated SQL function snapshots.

## Caller

The database-side `archive.github_send_function(...)` calls this function with:

- `function_history_id`
- one-time `publish_token`

The function does not accept arbitrary file paths or arbitrary SQL content.

## Authorization

`verify_jwt = false` is intentional. Authorization is the unguessable queue token,
which is validated against `archive.github_push_queue` by the service-role-only
RPC `public.get_function_publish_payload(...)`.

The publish token is rotated when a dead queue item is requeued.

## Environment

Required:

- `GITHUB_TOKEN`

Optional defaults:

- `GITHUB_OWNER=Antiokh`
- `GITHUB_REPO=dance-crm`
- `GITHUB_BRANCH=main`

Supabase runtime credentials are read from built-in
`SUPABASE_SECRET_KEYS` / `SUPABASE_SERVICE_ROLE_KEY`.

## Output

Generated files are written to:

`db/<schema>/<function_name>.sql`

Those files are generated artifacts and must not be edited manually.


## Cloudflare Pages

Generated commits are prefixed with `[CF-Pages-Skip]`.

Cloudflare Pages recognizes this prefix and skips the deployment for generated
Supabase export commits.

Supabase GitHub Integration should be filtered independently so generated
`db/**` commits do not cause unnecessary database deployment work.

