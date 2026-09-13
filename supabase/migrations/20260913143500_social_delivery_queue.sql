-- Dance CRM: durable social delivery queue with scheduled and transactional lanes.
-- The queue is transport-agnostic; secrets and provider-specific logic live in Edge Functions.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.social_posts (
  id uuid primary key default gen_random_uuid(),
  dedupe_key text not null unique,
  source_type text not null default 'manual',
  source_id text,
  source_title text,
  source_url text,
  status text not null default 'draft'
    check (status in ('draft','needs_review','approved','scheduled','partially_published','published','stale','cancelled')),
  approved_at timestamptz,
  approved_by text,
  target_publish_at timestamptz,
  stale_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_post_variants (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.social_posts(id) on delete cascade,
  platform text not null,
  variant_key text not null default 'default',
  body text not null default '',
  link_url text,
  character_limit integer check (character_limit is null or character_limit > 0),
  character_count integer generated always as (char_length(body)) stored,
  status text not null default 'draft'
    check (status in ('draft','needs_review','approved','rejected','stale')),
  validation jsonb not null default '{}'::jsonb,
  approved_at timestamptz,
  approved_by text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (post_id, platform, variant_key)
);

create table if not exists public.social_destinations (
  key text primary key,
  platform text not null,
  display_name text not null,
  enabled boolean not null default true,
  default_character_limit integer check (default_character_limit is null or default_character_limit > 0),
  settings jsonb not null default '{}'::jsonb,
  min_publish_interval_seconds integer not null default 0 check (min_publish_interval_seconds >= 0),
  last_claimed_at timestamptz,
  rate_limited_at timestamptz,
  retry_after_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_publication_jobs (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.social_post_variants(id) on delete cascade,
  destination_key text not null references public.social_destinations(key),
  idempotency_key text not null unique,

  queue_class text not null default 'scheduled'
    check (queue_class in ('scheduled','transactional')),
  priority integer not null default 0 check (priority between -1000 and 1000),

  status text not null default 'queued'
    check (status in ('queued','retry','leased','published','dead','cancelled')),
  scheduled_at timestamptz not null default now(),
  available_at timestamptz not null default now(),
  expires_at timestamptz,
  depends_on_job_id uuid references public.social_publication_jobs(id) on delete set null,

  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  lease_owner text,
  lease_expires_at timestamptz,

  published_at timestamptz,
  external_post_id text,
  external_post_url text,
  last_error text,
  provider_response jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (depends_on_job_id is null or depends_on_job_id <> id)
);

create index if not exists social_jobs_ready_idx
  on public.social_publication_jobs(queue_class, priority desc, available_at, scheduled_at, created_at)
  where status in ('queued','retry');

create index if not exists social_jobs_destination_idx
  on public.social_publication_jobs(destination_key, status, lease_expires_at);

create index if not exists social_jobs_dependency_idx
  on public.social_publication_jobs(depends_on_job_id)
  where depends_on_job_id is not null;

create index if not exists social_variants_post_idx
  on public.social_post_variants(post_id);

create or replace function public.social_touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists social_posts_touch_updated_at on public.social_posts;
create trigger social_posts_touch_updated_at
before update on public.social_posts
for each row execute function public.social_touch_updated_at();

drop trigger if exists social_variants_touch_updated_at on public.social_post_variants;
create trigger social_variants_touch_updated_at
before update on public.social_post_variants
for each row execute function public.social_touch_updated_at();

drop trigger if exists social_destinations_touch_updated_at on public.social_destinations;
create trigger social_destinations_touch_updated_at
before update on public.social_destinations
for each row execute function public.social_touch_updated_at();

drop trigger if exists social_jobs_touch_updated_at on public.social_publication_jobs;
create trigger social_jobs_touch_updated_at
before update on public.social_publication_jobs
for each row execute function public.social_touch_updated_at();

create or replace function public.social_schedule_variant(
  p_variant_id uuid,
  p_destination_key text,
  p_scheduled_at timestamptz default now(),
  p_queue_class text default 'scheduled',
  p_priority integer default 0,
  p_expires_at timestamptz default null,
  p_depends_on_job_id uuid default null,
  p_max_attempts integer default 5,
  p_metadata jsonb default '{}'::jsonb
)
returns public.social_publication_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_variant public.social_post_variants;
  v_post public.social_posts;
  v_destination public.social_destinations;
  v_job public.social_publication_jobs;
  v_key text;
  v_limit integer;
begin
  if p_queue_class not in ('scheduled','transactional') then
    raise exception 'invalid queue_class' using errcode = '22023';
  end if;
  if p_priority < -1000 or p_priority > 1000 then
    raise exception 'priority must be between -1000 and 1000' using errcode = '22023';
  end if;
  if p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception 'max_attempts must be between 1 and 20' using errcode = '22023';
  end if;
  if p_expires_at is not null and p_expires_at <= p_scheduled_at then
    raise exception 'expires_at must be after scheduled_at' using errcode = '22023';
  end if;

  select * into v_variant from public.social_post_variants where id = p_variant_id for update;
  if not found then raise exception 'social post variant not found' using errcode = 'P0002'; end if;
  if v_variant.status <> 'approved' then raise exception 'variant must be approved before scheduling' using errcode = '55000'; end if;

  select * into v_post from public.social_posts where id = v_variant.post_id for update;
  if not found then raise exception 'parent social post not found' using errcode = 'P0002'; end if;
  if v_post.status not in ('approved','scheduled','partially_published') then
    raise exception 'post status % does not allow scheduling', v_post.status using errcode = '55000';
  end if;

  select * into v_destination from public.social_destinations where key = p_destination_key;
  if not found then raise exception 'social destination not found' using errcode = 'P0002'; end if;
  if not v_destination.enabled then raise exception 'social destination is disabled' using errcode = '55000'; end if;
  if v_variant.platform <> v_destination.platform then
    raise exception 'variant platform % does not match destination platform %', v_variant.platform, v_destination.platform using errcode = '22023';
  end if;

  v_limit := coalesce(v_variant.character_limit, v_destination.default_character_limit);
  if v_limit is not null and v_variant.character_count > v_limit then
    raise exception 'variant exceeds destination character limit' using errcode = '22001';
  end if;

  if p_depends_on_job_id is not null and not exists (
    select 1 from public.social_publication_jobs where id = p_depends_on_job_id
  ) then
    raise exception 'dependency job not found' using errcode = 'P0002';
  end if;

  v_key := encode(digest(
    v_post.dedupe_key || ':' || p_destination_key || ':' || v_variant.variant_key || ':' || p_queue_class,
    'sha256'
  ), 'hex');

  select * into v_job
  from public.social_publication_jobs
  where idempotency_key = v_key
  for update;

  if found and v_job.status = 'published' then
    return v_job;
  elsif found and v_job.status = 'leased' and v_job.lease_expires_at > now() then
    raise exception 'cannot reschedule an actively leased publication job' using errcode = '55000';
  elsif found then
    update public.social_publication_jobs
    set variant_id = p_variant_id,
        destination_key = p_destination_key,
        queue_class = p_queue_class,
        priority = p_priority,
        status = 'queued',
        scheduled_at = p_scheduled_at,
        available_at = now(),
        expires_at = p_expires_at,
        depends_on_job_id = p_depends_on_job_id,
        attempt_count = 0,
        max_attempts = p_max_attempts,
        lease_owner = null,
        lease_expires_at = null,
        published_at = null,
        external_post_id = null,
        external_post_url = null,
        last_error = null,
        provider_response = '{}'::jsonb,
        metadata = coalesce(p_metadata, '{}'::jsonb)
    where id = v_job.id
    returning * into v_job;
  else
    insert into public.social_publication_jobs(
      variant_id, destination_key, idempotency_key, queue_class, priority,
      status, scheduled_at, available_at, expires_at, depends_on_job_id,
      max_attempts, metadata
    ) values (
      p_variant_id, p_destination_key, v_key, p_queue_class, p_priority,
      'queued', p_scheduled_at, now(), p_expires_at, p_depends_on_job_id,
      p_max_attempts, coalesce(p_metadata, '{}'::jsonb)
    ) returning * into v_job;
  end if;

  update public.social_posts
  set status = case when status = 'partially_published' then status else 'scheduled' end,
      target_publish_at = least(coalesce(target_publish_at, p_scheduled_at), p_scheduled_at)
  where id = v_post.id;

  return v_job;
end;
$$;

create or replace function public.social_claim_publication_jobs(
  p_worker_id text,
  p_transactional_limit integer default 8,
  p_scheduled_limit integer default 2,
  p_lease_seconds integer default 300
)
returns setof public.social_publication_jobs
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_lane text;
  v_lane_limit integer;
  v_claimed integer;
  v_job public.social_publication_jobs%rowtype;
  v_lease_seconds integer := least(greatest(coalesce(p_lease_seconds,300),60),3600);
begin
  if nullif(btrim(p_worker_id),'') is null then
    raise exception 'worker_id is required' using errcode = '22023';
  end if;

  -- Drop messages that are no longer useful. We never retry expired notifications.
  update public.social_publication_jobs
  set status = 'cancelled',
      last_error = coalesce(last_error, 'job expired before delivery'),
      lease_owner = null,
      lease_expires_at = null
  where status in ('queued','retry','leased')
    and expires_at is not null
    and expires_at <= now()
    and (status <> 'leased' or lease_expires_at <= now());

  -- Requeue expired leases. The attempt counter was already incremented at claim time.
  update public.social_publication_jobs
  set status = case when attempt_count >= max_attempts then 'dead' else 'retry' end,
      available_at = case when attempt_count >= max_attempts then available_at else now() + interval '60 seconds' end,
      last_error = coalesce(last_error, 'worker lease expired'),
      lease_owner = null,
      lease_expires_at = null
  where status = 'leased'
    and lease_expires_at <= now()
    and (expires_at is null or expires_at > now());

  foreach v_lane in array array['transactional','scheduled'] loop
    v_lane_limit := case
      when v_lane = 'transactional' then least(greatest(coalesce(p_transactional_limit,8),0),50)
      else least(greatest(coalesce(p_scheduled_limit,2),0),50)
    end;
    v_claimed := 0;

    while v_claimed < v_lane_limit loop
      select job.* into v_job
      from public.social_publication_jobs job
      join public.social_post_variants variant on variant.id = job.variant_id
      join public.social_posts post on post.id = variant.post_id
      join public.social_destinations destination on destination.key = job.destination_key
      where job.queue_class = v_lane
        and job.status in ('queued','retry')
        and job.attempt_count < job.max_attempts
        and job.scheduled_at <= now()
        and job.available_at <= now()
        and (job.expires_at is null or job.expires_at > now())
        and variant.status = 'approved'
        and post.status in ('approved','scheduled','partially_published')
        and destination.enabled
        and (destination.retry_after_at is null or destination.retry_after_at <= now())
        and (
          destination.last_claimed_at is null
          or destination.last_claimed_at <= now() - make_interval(secs => destination.min_publish_interval_seconds)
        )
        and not exists (
          select 1 from public.social_publication_jobs active
          where active.destination_key = job.destination_key
            and active.status = 'leased'
            and active.lease_expires_at > now()
        )
        and (
          job.depends_on_job_id is null
          or exists (
            select 1 from public.social_publication_jobs dependency
            where dependency.id = job.depends_on_job_id
              and dependency.status = 'published'
          )
        )
      order by job.priority desc, job.available_at, job.scheduled_at, job.created_at
      for update of job skip locked
      limit 1;

      exit when not found;

      update public.social_publication_jobs
      set status = 'leased',
          attempt_count = attempt_count + 1,
          lease_owner = btrim(p_worker_id),
          lease_expires_at = now() + make_interval(secs => v_lease_seconds),
          last_error = null
      where id = v_job.id
      returning * into v_job;

      update public.social_destinations
      set last_claimed_at = now()
      where key = v_job.destination_key;

      v_claimed := v_claimed + 1;
      return next v_job;
    end loop;
  end loop;
end;
$$;

create or replace function public.social_mark_publication_succeeded(
  p_job_id uuid,
  p_worker_id text,
  p_external_post_id text default null,
  p_external_post_url text default null,
  p_provider_response jsonb default '{}'::jsonb
)
returns public.social_publication_jobs
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_job public.social_publication_jobs;
  v_post_id uuid;
begin
  update public.social_publication_jobs
  set status = 'published', published_at = now(),
      external_post_id = p_external_post_id, external_post_url = p_external_post_url,
      provider_response = coalesce(p_provider_response,'{}'::jsonb),
      last_error = null, lease_owner = null, lease_expires_at = null
  where id = p_job_id and status = 'leased' and lease_owner = p_worker_id
  returning * into v_job;
  if not found then raise exception 'leased publication job not found for this worker' using errcode = 'P0002'; end if;

  select post_id into v_post_id from public.social_post_variants where id = v_job.variant_id;
  update public.social_posts
  set status = case
    when exists (
      select 1 from public.social_publication_jobs j
      join public.social_post_variants v on v.id=j.variant_id
      where v.post_id=v_post_id and j.status not in ('published','cancelled')
    ) then 'partially_published' else 'published' end
  where id = v_post_id and status not in ('stale','cancelled');

  return v_job;
end;
$$;

create or replace function public.social_mark_publication_failed(
  p_job_id uuid,
  p_worker_id text,
  p_error text,
  p_retry_after_seconds integer default 300,
  p_terminal boolean default false,
  p_provider_response jsonb default '{}'::jsonb
)
returns public.social_publication_jobs
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_job public.social_publication_jobs;
  v_retry integer := least(greatest(coalesce(p_retry_after_seconds,300),60),86400);
begin
  update public.social_publication_jobs
  set status = case when p_terminal or attempt_count >= max_attempts then 'dead' else 'retry' end,
      available_at = case when p_terminal or attempt_count >= max_attempts then available_at else now() + make_interval(secs => v_retry) end,
      last_error = coalesce(nullif(btrim(p_error),''),'unknown publication error'),
      provider_response = coalesce(p_provider_response,'{}'::jsonb),
      lease_owner = null,
      lease_expires_at = null
  where id = p_job_id and status = 'leased' and lease_owner = p_worker_id
  returning * into v_job;
  if not found then raise exception 'leased publication job not found for this worker' using errcode = 'P0002'; end if;
  return v_job;
end;
$$;

create or replace function public.social_set_destination_backoff(
  p_destination_key text,
  p_retry_after_at timestamptz,
  p_error text default null
)
returns public.social_destinations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_row public.social_destinations;
begin
  update public.social_destinations
  set rate_limited_at = now(), retry_after_at = p_retry_after_at, last_error = p_error
  where key = p_destination_key
  returning * into v_row;
  if not found then raise exception 'social destination not found' using errcode = 'P0002'; end if;
  return v_row;
end;
$$;

-- Backend-only subsystem for now. Edge Functions use the service role.
alter table public.social_posts enable row level security;
alter table public.social_post_variants enable row level security;
alter table public.social_destinations enable row level security;
alter table public.social_publication_jobs enable row level security;

revoke all on public.social_posts from anon, authenticated;
revoke all on public.social_post_variants from anon, authenticated;
revoke all on public.social_destinations from anon, authenticated;
revoke all on public.social_publication_jobs from anon, authenticated;
revoke execute on function public.social_schedule_variant(uuid,text,timestamptz,text,integer,timestamptz,uuid,integer,jsonb) from public, anon, authenticated;
revoke execute on function public.social_claim_publication_jobs(text,integer,integer,integer) from public, anon, authenticated;
revoke execute on function public.social_mark_publication_succeeded(uuid,text,text,text,jsonb) from public, anon, authenticated;
revoke execute on function public.social_mark_publication_failed(uuid,text,text,integer,boolean,jsonb) from public, anon, authenticated;
revoke execute on function public.social_set_destination_backoff(text,timestamptz,text) from public, anon, authenticated;
