import { readFileSync } from 'node:fs'

function read(path) {
  return readFileSync(path, 'utf8')
}

function fail(message) {
  console.error(`social-boundary: ${message}`)
  process.exitCode = 1
}

const config = read('supabase/config.toml')
const commandMigration = read(
  'supabase/migrations/20260927133000_social_command_queue.sql',
)
const publisherMigration = read(
  'supabase/migrations/20260927134000_social_publishing_core.sql',
)
const eventAdapterMigration = read(
  'supabase/migrations/20260927134500_event_social_adapter.sql',
)
const workerMigration = read(
  'supabase/migrations/20260927141000_social_dispatch_worker.sql',
)
const adminMigration = read(
  'supabase/migrations/20260927142000_social_admin_ops.sql',
)
const commandWorker = read('supabase/functions/social-command-worker/index.ts')
const dispatcher = read('supabase/functions/social-publish-dispatch/index.ts')

const apiSchemasMatch = config.match(/schemas\s*=\s*\[([^\]]*)\]/)
if (!apiSchemasMatch) {
  fail('could not find Supabase API schemas configuration')
} else if (/["']social["']/.test(apiSchemasMatch[1])) {
  fail('social schema must not be exposed through the Data API')
}

if (!/create schema if not exists social\s*;/i.test(publisherMigration)) {
  fail('private social schema is missing')
}

for (const [name, source] of [
  ['publisher migration', publisherMigration],
  ['worker migration', workerMigration],
  ['admin migration', adminMigration],
]) {
  if (/create\s+table\s+(?:if\s+not\s+exists\s+)?public\.social_(?:destinations|rate_limit_groups|publication_jobs|dispatch_config)/i.test(source)) {
    fail(`${name} creates publisher implementation state in public`)
  }
}

if (!/security\s+invoker/i.test(eventAdapterMigration)
  || !/function\s+public\.enqueue_social_command/i.test(eventAdapterMigration)) {
  fail('consumer enqueue API must remain SECURITY INVOKER')
}

for (const [name, source] of [
  ['social-command-worker', commandWorker],
  ['social-publish-dispatch', dispatcher],
]) {
  if (/\.from\(\s*['"](?:social_|event_social_publications|social_publication_jobs)/.test(source)) {
    fail(`${name} directly accesses private publisher tables through PostgREST`)
  }
}

if (!publisherMigration.includes('social.publications')
  || !publisherMigration.includes('social.delivery_jobs')
  || !publisherMigration.includes('social.destinations')) {
  fail('expected private publisher tables are missing')
}

if (/public\.(dance_events|event_attendance|dancer|venues|l_dance_style)|private\.has_app_role|public\.app_role/.test(commandMigration)) {
  fail('reusable command queue must not depend on Dance CRM domain/auth tables')
}

if (/public\.(dance_events|event_attendance|dancer|venues|l_dance_style)|private\.has_app_role|public\.app_role/.test(publisherMigration)) {
  fail('reusable social core must not depend on Dance CRM domain/auth tables')
}

if (/private\.has_app_role|public\.app_role|private\.current_dancer_id/.test(workerMigration)) {
  fail('reusable worker core must not depend on Dance CRM admin roles')
}

if (!/public\.dance_events/.test(eventAdapterMigration)
  || !/public\.enqueue_social_command/.test(eventAdapterMigration)) {
  fail('Dance event adapter must remain outside the reusable social core')
}

if (/social_get_event_publication_context|public\.dance_events|public\.event_attendance/.test(dispatcher)) {
  fail('delivery dispatcher must render from immutable social snapshots, not live Dance CRM tables')
}

if (process.exitCode) {
  process.exit(process.exitCode)
}

console.log('social-boundary: ok')
