-- Reusable private social publishing core.
-- No Dance CRM domain table is referenced by this migration.
-- Private publisher implementation. The public CRM remains the RLS-protected domain surface.
create schema if not exists social;
revoke all on schema social from public, anon, authenticated;
grant usage on schema social to service_role;

-- Durable, domain-driven social publication pipeline for dance events.
-- Based on the reduced Dobri Visarun pipeline and RSLive delivery semantics.

create table if not exists social.destinations (
  key text primary key,
  platform text not null,
  publisher text not null check (
    publisher in ('telegram_api', 'threads_api', 'instagram_api', 'make_webhook')
  ),
  display_name text not null,
  enabled boolean not null default false,
  rate_limit_group text,
  min_interval_ms integer not null default 1500
    check (min_interval_ms >= 0),
  max_attempts integer not null default 6
    check (max_attempts between 1 and 20),
  settings jsonb not null default '{}'::jsonb,
  last_claimed_at timestamptz,
  cooldown_until timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists social_destinations_touch_updated_at
  on social.destinations;
create trigger social_destinations_touch_updated_at
before update on social.destinations
for each row execute function private.touch_updated_at();

create table if not exists social.rate_limit_groups (
  key text primary key,
  min_interval_ms integer not null default 1500
    check (min_interval_ms >= 0),
  last_claimed_at timestamptz,
  cooldown_until timestamptz,
  updated_at timestamptz not null default now()
);

drop trigger if exists social_rate_limit_groups_touch_updated_at
  on social.rate_limit_groups;
create trigger social_rate_limit_groups_touch_updated_at
before update on social.rate_limit_groups
for each row execute function private.touch_updated_at();

create table if not exists social.publications (
  id uuid primary key default extensions.gen_random_uuid(),
  source_type text not null check (btrim(source_type) <> ''),
  source_id uuid not null,
  publication_type text not null check (btrim(publication_type) <> ''),
  version integer not null,
  transaction_id bigint not null default txid_current(),
  payload jsonb not null,
  status text not null default 'queued' check (
    status in ('queued', 'held', 'partial', 'published', 'failed', 'cancelled')
  ),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (source_type, source_id, version)
);

create index if not exists event_social_publications_event_idx
  on social.publications (source_type, source_id, version desc);

create table if not exists social.delivery_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  publication_id uuid not null
    references social.publications(id) on delete cascade,
  destination_key text not null
    references social.destinations(key) on delete restrict,
  operation text not null default 'publish'
    check (operation in ('publish', 'edit')),
  lane text not null default 'transactional'
    check (lane in ('transactional', 'scheduled')),
  expires_at timestamptz,
  depends_on_job_id uuid references social.delivery_jobs(id) on delete set null,
  idempotency_key text not null unique,
  status text not null default 'queued' check (
    status in ('queued', 'leased', 'retry', 'published', 'dead', 'cancelled')
  ),
  priority integer not null default 100,
  attempt_count integer not null default 0,
  max_attempts integer not null default 6,
  available_at timestamptz not null default now(),
  lease_owner text,
  lease_expires_at timestamptz,
  publish_started_at timestamptz,
  provider_progress jsonb not null default '{}'::jsonb,
  external_post_id text,
  external_post_url text,
  provider_response jsonb,
  last_error text,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (publication_id, destination_key)
);

create index if not exists social_publication_jobs_ready_idx
  on social.delivery_jobs (
    status,
    available_at,
    priority desc,
    created_at
  );

create index if not exists social_publication_jobs_lease_idx
  on social.delivery_jobs (lease_expires_at)
  where status = 'leased';

drop trigger if exists social_publication_jobs_touch_updated_at
  on social.delivery_jobs;
create trigger social_publication_jobs_touch_updated_at
before update on social.delivery_jobs
for each row execute function private.touch_updated_at();

alter table social.destinations enable row level security;
alter table social.rate_limit_groups enable row level security;
alter table social.publications enable row level security;
alter table social.delivery_jobs enable row level security;

revoke all on social.destinations from anon, authenticated;
revoke all on social.rate_limit_groups from anon, authenticated;
revoke all on social.publications from anon, authenticated;
revoke all on social.delivery_jobs from anon, authenticated;

grant all on social.destinations to service_role;
grant all on social.rate_limit_groups to service_role;
grant all on social.publications to service_role;
grant all on social.delivery_jobs to service_role;

insert into social.rate_limit_groups (key, min_interval_ms)
values
  ('telegram', 1100),
  ('meta_api', 2500),
  ('make', 1500)
on conflict (key) do nothing;

insert into social.destinations (
  key,
  platform,
  publisher,
  display_name,
  enabled,
  rate_limit_group,
  min_interval_ms,
  settings
)
values
  (
    'telegram',
    'telegram',
    'telegram_api',
    'Telegram',
    false,
    'telegram',
    1100,
    jsonb_build_object(
      'parse_mode', 'HTML'
    )
  ),
  (
    'threads',
    'threads',
    'threads_api',
    'Threads',
    false,
    'meta_api',
    2500,
    '{}'::jsonb
  ),
  (
    'instagram',
    'instagram',
    'instagram_api',
    'Instagram',
    false,
    'meta_api',
    2500,
    '{}'::jsonb
  ),
  (
    'facebook',
    'facebook',
    'make_webhook',
    'Facebook',
    false,
    'make',
    1500,
    jsonb_build_object('destination', 'facebook')
  )
on conflict (key) do update
set platform = excluded.platform,
    publisher = excluded.publisher,
    display_name = excluded.display_name,
    rate_limit_group = excluded.rate_limit_group,
    min_interval_ms = excluded.min_interval_ms,
    settings = social.destinations.settings || excluded.settings;

create or replace function private.refresh_social_publication_status(
  p_publication_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_total integer;
  v_published integer;
  v_active integer;
  v_dead integer;
  v_cancelled integer;
begin
  select
    count(*)::integer,
    count(*) filter (where j.status = 'published')::integer,
    count(*) filter (
      where j.status in ('queued', 'leased', 'retry')
    )::integer,
    count(*) filter (where j.status = 'dead')::integer,
    count(*) filter (where j.status = 'cancelled')::integer
  into v_total, v_published, v_active, v_dead, v_cancelled
  from social.delivery_jobs j
  where j.publication_id = p_publication_id;

  update social.publications p
  set status = case
        when v_total = 0 then 'held'
        when v_active > 0 and v_published > 0 then 'partial'
        when v_active > 0 then 'queued'
        when v_published = v_total then 'published'
        when v_published > 0 then 'partial'
        when v_dead > 0 then 'failed'
        when v_cancelled = v_total then 'cancelled'
        else p.status
      end,
      completed_at = case
        when v_total > 0 and v_active = 0
          then coalesce(p.completed_at, now())
        else null
      end
  where p.id = p_publication_id;
end;
$function$;

revoke all on function private.refresh_social_publication_status(uuid)
  from public, anon, authenticated;

create or replace function public.social_get_destination(
  p_key text
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'key', d.key,
    'platform', d.platform,
    'publisher', d.publisher,
    'enabled', d.enabled,
    'settings', d.settings
  )
  from social.destinations d
  where d.key = p_key
$function$;

revoke all on function public.social_get_destination(text)
  from public, anon, authenticated;
grant execute on function public.social_get_destination(text)
  to service_role;

create or replace function public.social_get_publication_context(
  p_publication_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with target as (
    select
      p.id,
      p.source_type,
      p.source_id,
      p.publication_type,
      p.version,
      p.payload
    from social.publications p
    where p.id = p_publication_id
  ),
  telegram as (
    select
      j.external_post_id,
      j.external_post_url,
      j.provider_response
    from social.delivery_jobs j
    join social.publications p
      on p.id = j.publication_id
    join target t
      on t.source_type = p.source_type
     and t.source_id = p.source_id
    join social.destinations d
      on d.key = j.destination_key
    where d.publisher = 'telegram_api'
      and j.status = 'published'
      and j.external_post_id is not null
      and p.publication_type <> 'rsvp_update'
      and p.version <= t.version
    order by p.version desc, j.published_at desc nulls last
    limit 1
  )
  select jsonb_build_object(
    'publication_id', t.id,
    'source_type', t.source_type,
    'source_id', t.source_id,
    'publication_type', t.publication_type,
    'version', t.version,
    'payload', t.payload,
    'telegram_message', (
      select jsonb_build_object(
        'message_id', tg.external_post_id,
        'url', tg.external_post_url,
        'provider_response', tg.provider_response
      )
      from telegram tg
    )
  )
  from target t
$function$;

revoke all on function public.social_get_publication_context(uuid)
  from public, anon, authenticated;
grant execute on function public.social_get_publication_context(uuid)
  to service_role;

drop function if exists public.social_get_event_publication_context(uuid);

create or replace function public.social_mark_publish_started(
  p_job_id uuid,
  p_worker text,
  p_progress jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_publication_id uuid;
  v_source_type text;
  v_source_id uuid;
  v_version integer;
  v_created_at timestamptz;
begin
  select
    p.id,
    p.source_type,
    p.source_id,
    p.version,
    p.created_at
  into
    v_publication_id,
    v_source_type,
    v_source_id,
    v_version,
    v_created_at
  from social.delivery_jobs j
  join social.publications p on p.id = j.publication_id
  where j.id = p_job_id
    and j.status = 'leased'
    and j.lease_owner = p_worker
    and j.lease_expires_at > now()
  for update of j;

  if not found then
    return false;
  end if;

  if exists (
    select 1
    from social.publications newer
    where newer.source_type = v_source_type
      and newer.source_id = v_source_id
      and newer.version > v_version
  ) or exists (
    select 1
    from public.social_commands command
    where command.source_type = v_source_type
      and command.source_id = v_source_id
      and command.created_at > v_created_at
      and command.status in ('queued', 'leased', 'retry')
  ) then
    update social.delivery_jobs j
    set status = 'cancelled',
        lease_owner = null,
        lease_expires_at = null,
        last_error = 'Superseded by newer source command before provider call'
    where j.id = p_job_id
      and j.status = 'leased'
      and j.lease_owner = p_worker;

    perform private.refresh_social_publication_status(v_publication_id);
    return false;
  end if;

  update social.delivery_jobs j
  set publish_started_at = coalesce(j.publish_started_at, now()),
      provider_progress = j.provider_progress || coalesce(p_progress, '{}'::jsonb)
  where j.id = p_job_id
    and j.status = 'leased'
    and j.lease_owner = p_worker
    and j.lease_expires_at > now();

  return found;
end;
$function$;

revoke all on function public.social_mark_publish_started(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.social_mark_publish_started(uuid, text, jsonb)
  to service_role;

create or replace function public.social_patch_job_progress(
  p_job_id uuid,
  p_worker text,
  p_progress jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update social.delivery_jobs j
  set provider_progress =
        j.provider_progress || coalesce(p_progress, '{}'::jsonb)
  where j.id = p_job_id
    and j.status = 'leased'
    and j.lease_owner = p_worker
    and j.lease_expires_at > now();

  return found;
end;
$function$;

revoke all on function public.social_patch_job_progress(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.social_patch_job_progress(uuid, text, jsonb)
  to service_role;

create or replace function public.social_claim_publication_jobs(
  p_worker text,
  p_limit integer default 8,
  p_lease_seconds integer default 90
)
returns table(
  job_id uuid,
  publication_id uuid,
  destination_key text,
  publisher text,
  platform text,
  operation text,
  settings jsonb,
  publication_type text,
  source_type text,
  source_id uuid,
  payload jsonb,
  attempt_count integer,
  max_attempts integer,
  provider_progress jsonb
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_now timestamptz := now();
  v_limit integer := least(greatest(coalesce(p_limit, 8), 1), 32);
  v_lease_seconds integer :=
    least(greatest(coalesce(p_lease_seconds, 90), 30), 600);
  v_reaped_publication uuid;
begin
  if p_worker is null or btrim(p_worker) = '' then
    raise exception 'worker id required' using errcode = '22023';
  end if;

  for v_reaped_publication in
    with expired as (
      update social.delivery_jobs j
      set status = 'cancelled',
          last_error = 'Delivery job expired before publication',
          lease_owner = null,
          lease_expires_at = null
      where j.status in ('queued', 'retry')
        and j.expires_at is not null
        and j.expires_at <= v_now
      returning j.publication_id
    )
    select distinct e.publication_id
    from expired e
  loop
    perform private.refresh_social_publication_status(
      v_reaped_publication
    );
  end loop;

  for v_reaped_publication in
    with reaped as (
      update social.delivery_jobs j
      set status = case
            when j.publish_started_at is not null
              and coalesce(j.provider_progress->>'safe_retry', 'false') <> 'true'
              then 'dead'
            when j.attempt_count >= j.max_attempts
              then 'dead'
            else 'retry'
          end,
          available_at = case
            when j.attempt_count >= j.max_attempts then j.available_at
            else greatest(j.available_at, v_now + interval '30 seconds')
          end,
          last_error = case
            when j.publish_started_at is not null
              and coalesce(j.provider_progress->>'safe_retry', 'false') <> 'true'
              then 'Lease expired after provider publish started; automatic retry blocked to prevent duplicate publication'
            else 'Worker lease expired'
          end,
          lease_owner = null,
          lease_expires_at = null
      where j.status = 'leased'
        and j.lease_expires_at <= v_now
      returning j.publication_id
    )
    select distinct r.publication_id
    from reaped r
  loop
    perform private.refresh_social_publication_status(
      v_reaped_publication
    );
  end loop;

  return query
  with eligible as (
    select
      j.id,
      j.priority,
      j.available_at,
      j.created_at,
      j.priority
        + least(
            120,
            greatest(
              0,
              floor(extract(epoch from (v_now - j.created_at)) / 60)::integer
            )
          ) as effective_priority,
      row_number() over (
        partition by coalesce(d.rate_limit_group, 'destination:' || d.key)
        order by
          j.priority
            + least(
                120,
                greatest(
                  0,
                  floor(extract(epoch from (v_now - j.created_at)) / 60)::integer
                )
              ) desc,
          j.available_at,
          j.created_at
      ) as gate_rank
    from social.delivery_jobs j
    join social.publications p
      on p.id = j.publication_id
    join social.destinations d
      on d.key = j.destination_key
    left join social.rate_limit_groups g
      on g.key = d.rate_limit_group
    where j.status in ('queued', 'retry')
      and j.available_at <= v_now
      and j.attempt_count < j.max_attempts
      and (j.expires_at is null or j.expires_at > v_now)
      and (
        j.depends_on_job_id is null
        or exists (
          select 1
          from social.delivery_jobs dependency
          where dependency.id = j.depends_on_job_id
            and dependency.status = 'published'
        )
      )
      and d.enabled
      and not exists (
        select 1
        from social.publications newer
        where newer.source_type = p.source_type
          and newer.source_id = p.source_id
          and newer.version > p.version
      )
      and not exists (
        select 1
        from public.social_commands command
        where command.source_type = p.source_type
          and command.source_id = p.source_id
          and command.created_at > p.created_at
          and command.status in ('queued', 'leased', 'retry')
      )
      and coalesce(d.cooldown_until, '-infinity'::timestamptz) <= v_now
      and (
        d.last_claimed_at is null
        or d.last_claimed_at
          + make_interval(secs => d.min_interval_ms::double precision / 1000.0)
          <= v_now
      )
      and (
        g.key is null
        or (
          coalesce(g.cooldown_until, '-infinity'::timestamptz) <= v_now
          and (
            g.last_claimed_at is null
            or g.last_claimed_at
              + make_interval(secs => g.min_interval_ms::double precision / 1000.0)
              <= v_now
          )
        )
      )
  ),
  candidates as (
    select j.id
    from social.delivery_jobs j
    join eligible e on e.id = j.id
    where e.gate_rank = 1
    order by e.effective_priority desc, e.available_at, e.created_at
    for update of j skip locked
    limit v_limit
  ),
  claimed as (
    update social.delivery_jobs j
    set status = 'leased',
        attempt_count = j.attempt_count + 1,
        lease_owner = p_worker,
        lease_expires_at = v_now + make_interval(secs => v_lease_seconds),
        last_error = null
    from candidates c
    where j.id = c.id
    returning j.*
  ),
  touched_destinations as (
    update social.destinations d
    set last_claimed_at = v_now
    where d.key in (select c.destination_key from claimed c)
    returning d.key, d.rate_limit_group
  ),
  touched_groups as (
    update social.rate_limit_groups g
    set last_claimed_at = v_now
    where g.key in (
      select distinct td.rate_limit_group
      from touched_destinations td
      where td.rate_limit_group is not null
    )
    returning g.key
  )
  select
    c.id,
    c.publication_id,
    c.destination_key,
    d.publisher,
    d.platform,
    c.operation,
    d.settings,
    p.publication_type,
    p.source_type,
    p.source_id,
    p.payload,
    c.attempt_count,
    c.max_attempts,
    c.provider_progress
  from claimed c
  join social.destinations d
    on d.key = c.destination_key
  join social.publications p
    on p.id = c.publication_id
  order by c.priority desc, c.created_at;
end;
$function$;

revoke all on function public.social_claim_publication_jobs(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.social_claim_publication_jobs(text, integer, integer)
  to service_role;

create or replace function public.social_mark_publication_success(
  p_job_id uuid,
  p_worker text,
  p_external_post_id text default null,
  p_external_post_url text default null,
  p_provider_response jsonb default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_publication_id uuid;
  v_destination_key text;
  v_rate_limit_group text;
begin
  update social.delivery_jobs j
  set status = 'published',
      external_post_id = p_external_post_id,
      external_post_url = p_external_post_url,
      provider_response = p_provider_response,
      published_at = now(),
      lease_owner = null,
      lease_expires_at = null,
      last_error = null
  where j.id = p_job_id
    and j.status = 'leased'
    and j.lease_owner = p_worker
    and j.lease_expires_at > now()
  returning j.publication_id, j.destination_key
  into v_publication_id, v_destination_key;

  if not found then
    return false;
  end if;

  update social.destinations d
  set last_error = null,
      cooldown_until = null
  where d.key = v_destination_key
  returning d.rate_limit_group into v_rate_limit_group;

  if v_rate_limit_group is not null then
    update social.rate_limit_groups g
    set cooldown_until = null
    where g.key = v_rate_limit_group
      and coalesce(g.cooldown_until, '-infinity'::timestamptz) <= now();
  end if;

  perform private.refresh_social_publication_status(v_publication_id);
  return true;
end;
$function$;

revoke all on function public.social_mark_publication_success(
  uuid, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.social_mark_publication_success(
  uuid, text, text, text, jsonb
) to service_role;

create or replace function public.social_mark_publication_failure(
  p_job_id uuid,
  p_worker text,
  p_error text,
  p_retry_after_seconds integer default 60,
  p_provider_response jsonb default null,
  p_terminal boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_publication_id uuid;
  v_destination_key text;
  v_rate_limit_group text;
  v_status text;
  v_retry_seconds integer :=
    least(greatest(coalesce(p_retry_after_seconds, 60), 1), 86400);
begin
  select
    j.publication_id,
    j.destination_key,
    case
      when p_terminal or j.attempt_count >= j.max_attempts
        then 'dead'
      else 'retry'
    end
  into v_publication_id, v_destination_key, v_status
  from social.delivery_jobs j
  where j.id = p_job_id
    and j.status = 'leased'
    and j.lease_owner = p_worker
    and j.lease_expires_at > now()
  for update;

  if not found then
    return false;
  end if;

  update social.delivery_jobs j
  set status = v_status,
      available_at = case
        when v_status = 'retry'
          then now() + make_interval(secs => v_retry_seconds)
        else j.available_at
      end,
      provider_response = coalesce(p_provider_response, j.provider_response),
      last_error = left(coalesce(p_error, 'Unknown provider error'), 4000),
      lease_owner = null,
      lease_expires_at = null
  where j.id = p_job_id;

  select d.rate_limit_group
  into v_rate_limit_group
  from social.destinations d
  where d.key = v_destination_key;

  if v_status = 'retry' then
    update social.destinations
    set cooldown_until = greatest(
          coalesce(cooldown_until, '-infinity'::timestamptz),
          now() + make_interval(secs => v_retry_seconds)
        ),
        last_error = left(coalesce(p_error, 'Unknown provider error'), 4000)
    where key = v_destination_key;

    if v_rate_limit_group is not null then
      update social.rate_limit_groups
      set cooldown_until = greatest(
            coalesce(cooldown_until, '-infinity'::timestamptz),
            now() + make_interval(secs => v_retry_seconds)
          )
      where key = v_rate_limit_group;
    end if;
  end if;

  perform private.refresh_social_publication_status(v_publication_id);
  return true;
end;
$function$;

revoke all on function public.social_mark_publication_failure(
  uuid, text, text, integer, jsonb, boolean
) from public, anon, authenticated;
grant execute on function public.social_mark_publication_failure(
  uuid, text, text, integer, jsonb, boolean
) to service_role;
