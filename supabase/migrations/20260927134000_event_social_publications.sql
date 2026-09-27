-- Durable, domain-driven social publication pipeline for dance events.
-- Based on the reduced Dobri Visarun pipeline and RSLive delivery semantics.

create table if not exists public.social_destinations (
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
  on public.social_destinations;
create trigger social_destinations_touch_updated_at
before update on public.social_destinations
for each row execute function private.touch_updated_at();

create table if not exists public.social_rate_limit_groups (
  key text primary key,
  min_interval_ms integer not null default 1500
    check (min_interval_ms >= 0),
  last_claimed_at timestamptz,
  cooldown_until timestamptz,
  updated_at timestamptz not null default now()
);

drop trigger if exists social_rate_limit_groups_touch_updated_at
  on public.social_rate_limit_groups;
create trigger social_rate_limit_groups_touch_updated_at
before update on public.social_rate_limit_groups
for each row execute function private.touch_updated_at();

create table if not exists public.event_social_publications (
  id uuid primary key default extensions.gen_random_uuid(),
  event_id uuid not null references public.dance_events(id) on delete cascade,
  publication_type text not null check (
    publication_type in ('announcement', 'updated', 'cancelled', 'rsvp_update')
  ),
  version integer not null,
  transaction_id bigint not null default txid_current(),
  payload jsonb not null,
  status text not null default 'queued' check (
    status in ('queued', 'held', 'partial', 'published', 'failed', 'cancelled')
  ),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (event_id, version)
);

create index if not exists event_social_publications_event_idx
  on public.event_social_publications (event_id, version desc);

create table if not exists public.social_publication_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  publication_id uuid not null
    references public.event_social_publications(id) on delete cascade,
  destination_key text not null
    references public.social_destinations(key) on delete restrict,
  operation text not null default 'publish'
    check (operation in ('publish', 'edit')),
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
  on public.social_publication_jobs (
    status,
    available_at,
    priority desc,
    created_at
  );

create index if not exists social_publication_jobs_lease_idx
  on public.social_publication_jobs (lease_expires_at)
  where status = 'leased';

drop trigger if exists social_publication_jobs_touch_updated_at
  on public.social_publication_jobs;
create trigger social_publication_jobs_touch_updated_at
before update on public.social_publication_jobs
for each row execute function private.touch_updated_at();

alter table public.social_destinations enable row level security;
alter table public.social_rate_limit_groups enable row level security;
alter table public.event_social_publications enable row level security;
alter table public.social_publication_jobs enable row level security;

revoke all on public.social_destinations from anon, authenticated;
revoke all on public.social_rate_limit_groups from anon, authenticated;
revoke all on public.event_social_publications from anon, authenticated;
revoke all on public.social_publication_jobs from anon, authenticated;

grant all on public.social_destinations to service_role;
grant all on public.social_rate_limit_groups to service_role;
grant all on public.event_social_publications to service_role;
grant all on public.social_publication_jobs to service_role;

insert into public.social_rate_limit_groups (key, min_interval_ms)
values
  ('telegram', 1100),
  ('meta_api', 2500),
  ('make', 1500)
on conflict (key) do nothing;

insert into public.social_destinations (
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
    settings = public.social_destinations.settings || excluded.settings;

create or replace function private.event_social_payload(
  p_event_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'event_id', e.id,
    'event_type', e.event_type,
    'title', e.title,
    'description', e.description,
    'announcement_image_url', e.announcement_image_url,
    'starts_at', e.starts_at,
    'ends_at', e.ends_at,
    'published', e.published,
    'cancelled_at', e.cancelled_at,
    'leader_going_count', e.leader_going_count,
    'follower_going_count', e.follower_going_count,
    'other_going_count', e.other_going_count,
    'venue',
      case when v.id is null then null else jsonb_build_object(
        'id', v.id,
        'name', v.name,
        'address', v.address,
        'latitude', v.latitude,
        'longitude', v.longitude
      ) end,
    'style',
      case when s.id is null then null else jsonb_build_object(
        'id', s.id,
        'title_en', s.title_en,
        'title_ru', s.title_ru,
        'title_sr', s.title_sr,
        'is_partner_dance', s.is_partner_dance
      ) end
  )
  from public.dance_events e
  left join public.venues v on v.id = e.venue_id
  left join public.l_dance_style s on s.id = e.style_id
  where e.id = p_event_id
$function$;

revoke all on function private.event_social_payload(uuid)
  from public, anon, authenticated;

create or replace function private.refresh_event_social_publication_status(
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
  from public.social_publication_jobs j
  where j.publication_id = p_publication_id;

  update public.event_social_publications p
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

revoke all on function private.refresh_event_social_publication_status(uuid)
  from public, anon, authenticated;

create or replace function private.schedule_event_social_jobs(
  p_publication_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_publication public.event_social_publications%rowtype;
  v_inserted integer := 0;
begin
  select *
  into v_publication
  from public.event_social_publications p
  where p.id = p_publication_id;

  if not found then
    raise exception 'social publication not found' using errcode = 'P0002';
  end if;

  insert into public.social_publication_jobs (
    publication_id,
    destination_key,
    operation,
    idempotency_key,
    priority,
    max_attempts
  )
  select
    v_publication.id,
    d.key,
    case
      when v_publication.publication_type = 'rsvp_update'
        and d.publisher = 'telegram_api'
      then 'edit'
      else 'publish'
    end,
    v_publication.id::text || ':' || d.key,
    case
      when v_publication.publication_type = 'cancelled' then 400
      when v_publication.publication_type in ('announcement', 'updated') then 300
      when v_publication.publication_type = 'rsvp_update' then 200
      else 100
    end,
    d.max_attempts
  from public.social_destinations d
  where d.enabled
    and (
      v_publication.publication_type <> 'rsvp_update'
      or d.publisher = 'telegram_api'
    )
    and (
      v_publication.publication_type <> 'cancelled'
      or exists (
        select 1
        from public.social_publication_jobs prior_job
        join public.event_social_publications prior_publication
          on prior_publication.id = prior_job.publication_id
        where prior_publication.event_id = v_publication.event_id
          and prior_publication.id <> v_publication.id
          and prior_job.destination_key = d.key
          and prior_job.status = 'published'
      )
    )
  on conflict (publication_id, destination_key) do nothing;

  get diagnostics v_inserted = row_count;

  perform private.refresh_event_social_publication_status(v_publication.id);
  return v_inserted;
end;
$function$;

revoke all on function private.schedule_event_social_jobs(uuid)
  from public, anon, authenticated;

create or replace function private.queue_event_social_publication(
  p_event_id uuid,
  p_publication_type text,
  p_transaction_id bigint default txid_current()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_version integer;
  v_publication_id uuid;
  v_payload jsonb;
  v_old_publication_id uuid;
begin
  if p_publication_type not in (
    'announcement',
    'updated',
    'cancelled',
    'rsvp_update'
  ) then
    raise exception 'invalid publication type' using errcode = '22023';
  end if;

  perform 1
  from public.dance_events e
  where e.id = p_event_id
  for update;

  if not found then
    raise exception 'event not found' using errcode = 'P0002';
  end if;

  if p_publication_type = 'rsvp_update' then
    for v_old_publication_id in
      select p.id
      from public.event_social_publications p
      where p.event_id = p_event_id
        and p.publication_type = 'rsvp_update'
        and p.status in ('queued', 'held', 'partial')
      order by p.version desc
    loop
      update public.social_publication_jobs j
      set status = 'cancelled',
          lease_owner = null,
          lease_expires_at = null,
          last_error = 'Superseded by newer RSVP state'
      where j.publication_id = v_old_publication_id
        and j.status in ('queued', 'retry');

      perform private.refresh_event_social_publication_status(
        v_old_publication_id
      );
    end loop;
  else
    for v_old_publication_id in
      select p.id
      from public.event_social_publications p
      where p.event_id = p_event_id
        and p.publication_type <> 'rsvp_update'
        and p.status in ('queued', 'held', 'partial')
      order by p.version desc
    loop
      update public.social_publication_jobs j
      set status = 'cancelled',
          lease_owner = null,
          lease_expires_at = null,
          last_error = 'Superseded by newer event publication'
      where j.publication_id = v_old_publication_id
        and j.status in ('queued', 'retry');

      perform private.refresh_event_social_publication_status(
        v_old_publication_id
      );
    end loop;
  end if;

  select coalesce(max(p.version), 0) + 1
  into v_version
  from public.event_social_publications p
  where p.event_id = p_event_id;

  v_payload := private.event_social_payload(p_event_id);

  insert into public.event_social_publications (
    event_id,
    publication_type,
    version,
    transaction_id,
    payload
  )
  values (
    p_event_id,
    p_publication_type,
    v_version,
    coalesce(p_transaction_id, txid_current()),
    v_payload
  )
  returning id into v_publication_id;

  perform private.schedule_event_social_jobs(v_publication_id);
  return v_publication_id;
end;
$function$;

revoke all on function private.queue_event_social_publication(
  uuid,
  text,
  bigint
) from public, anon, authenticated;

create or replace function private.event_social_change_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_type text;
  v_publication_id uuid;
begin
  if tg_op = 'INSERT' then
    if new.published and new.cancelled_at is null then
      perform private.queue_event_social_publication(
        new.id,
        'announcement',
        txid_current()
      );
    end if;
    return new;
  end if;

  if old.published and not new.published then
    update public.social_publication_jobs j
    set status = 'cancelled',
        lease_owner = null,
        lease_expires_at = null,
        last_error = 'Event was unpublished before delivery'
    where j.publication_id in (
      select p.id
      from public.event_social_publications p
      where p.event_id = new.id
    )
      and j.status in ('queued', 'retry');

    for v_publication_id in
      select p.id
      from public.event_social_publications p
      where p.event_id = new.id
        and p.status in ('queued', 'held', 'partial')
    loop
      perform private.refresh_event_social_publication_status(
        v_publication_id
      );
    end loop;

    return new;
  end if;

  if old.cancelled_at is null and new.cancelled_at is not null
    and (old.published or new.published)
  then
    v_type := 'cancelled';
  elsif not old.published and new.published
    and new.cancelled_at is null
  then
    v_type := 'announcement';
  elsif new.published
    and new.cancelled_at is null
    and (
      old.event_type is distinct from new.event_type
      or old.title is distinct from new.title
      or old.description is distinct from new.description
      or old.announcement_image_url is distinct from new.announcement_image_url
      or old.starts_at is distinct from new.starts_at
      or old.ends_at is distinct from new.ends_at
      or old.venue_id is distinct from new.venue_id
      or old.style_id is distinct from new.style_id
    )
  then
    v_type := 'updated';
  end if;

  if v_type is not null then
    perform private.queue_event_social_publication(
      new.id,
      v_type,
      txid_current()
    );
  end if;

  return new;
end;
$function$;

revoke all on function private.event_social_change_trigger()
  from public, anon, authenticated;

drop trigger if exists dance_events_social_publication
  on public.dance_events;
create trigger dance_events_social_publication
after insert or update of
  event_type,
  title,
  description,
  announcement_image_url,
  starts_at,
  ends_at,
  venue_id,
  style_id,
  published,
  cancelled_at
on public.dance_events
for each row execute function private.event_social_change_trigger();

create or replace function private.event_attendance_social_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_old_going boolean := false;
  v_new_going boolean := false;
  v_event_id uuid;
begin
  v_event_id := case when tg_op = 'DELETE' then old.event_id else new.event_id end;

  if tg_op <> 'INSERT' then
    v_old_going :=
      old.cancelled_at is null
      and old.response = 'going'::public.event_rsvp_response;
  end if;

  if tg_op <> 'DELETE' then
    v_new_going :=
      new.cancelled_at is null
      and new.response = 'going'::public.event_rsvp_response;
  end if;

  if v_old_going is distinct from v_new_going
    or (
      v_old_going
      and v_new_going
      and old.role_id is distinct from new.role_id
    )
  then
    if exists (
      select 1
      from public.dance_events e
      where e.id = v_event_id
        and e.published
        and e.cancelled_at is null
        and coalesce(e.ends_at, e.starts_at) > now()
    ) then
      perform private.queue_event_social_publication(
        v_event_id,
        'rsvp_update',
        txid_current()
      );
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

revoke all on function private.event_attendance_social_trigger()
  from public, anon, authenticated;

drop trigger if exists event_attendance_social_publication
  on public.event_attendance;
create trigger event_attendance_social_publication
after insert or delete or update of response, role_id, cancelled_at
on public.event_attendance
for each row execute function private.event_attendance_social_trigger();

create or replace function public.admin_queue_event_social_publication(
  p_event_id uuid,
  p_publication_type text default 'announcement'
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;

  return private.queue_event_social_publication(
    p_event_id,
    p_publication_type,
    txid_current()
  );
end;
$function$;

revoke all on function public.admin_queue_event_social_publication(uuid, text)
  from public, anon;
grant execute on function public.admin_queue_event_social_publication(uuid, text)
  to authenticated;

create or replace function public.social_get_event_publication_context(
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
      p.event_id,
      p.publication_type,
      p.version,
      p.payload,
      e.leader_going_count,
      e.follower_going_count,
      e.other_going_count
    from public.event_social_publications p
    join public.dance_events e on e.id = p.event_id
    where p.id = p_publication_id
  ),
  attendees as (
    select
      ea.event_id,
      coalesce(
        nullif(btrim(d.custom_name), ''),
        nullif(btrim(concat_ws(' ', d.first_name, d.last_name)), ''),
        case
          when nullif(btrim(d.telegram_username), '') is not null
            then '@' || btrim(d.telegram_username)
          else null
        end,
        'Танцор'
      ) as name,
      ea.role_id,
      ea.responded_at
    from public.event_attendance ea
    join public.dancer d on d.id = ea.dancer_id
    join target t on t.event_id = ea.event_id
    where ea.cancelled_at is null
      and ea.response = 'going'::public.event_rsvp_response
  ),
  telegram as (
    select
      j.external_post_id,
      j.external_post_url,
      j.provider_response
    from public.social_publication_jobs j
    join public.event_social_publications p
      on p.id = j.publication_id
    join target t on t.event_id = p.event_id
    join public.social_destinations d
      on d.key = j.destination_key
    where d.publisher = 'telegram_api'
      and j.status = 'published'
      and j.external_post_id is not null
      and p.publication_type <> 'rsvp_update'
    order by p.version desc, j.published_at desc nulls last
    limit 1
  )
  select jsonb_build_object(
    'publication_id', t.id,
    'event_id', t.event_id,
    'publication_type', t.publication_type,
    'version', t.version,
    'payload', t.payload,
    'balance', jsonb_build_object(
      'leader', t.leader_going_count,
      'follower', t.follower_going_count,
      'other', t.other_going_count,
      'total',
        t.leader_going_count
        + t.follower_going_count
        + t.other_going_count
    ),
    'attendees', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'name', a.name,
          'role_id', a.role_id,
          'responded_at', a.responded_at
        )
        order by
          case a.role_id when 1 then 1 when 2 then 2 else 3 end,
          a.name
      )
      from attendees a
    ), '[]'::jsonb),
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

revoke all on function public.social_get_event_publication_context(uuid)
  from public, anon, authenticated;
grant execute on function public.social_get_event_publication_context(uuid)
  to service_role;

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
begin
  update public.social_publication_jobs j
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
  update public.social_publication_jobs j
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
  event_id uuid,
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
begin
  if p_worker is null or btrim(p_worker) = '' then
    raise exception 'worker id required' using errcode = '22023';
  end if;

  update public.social_publication_jobs j
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
    and j.lease_expires_at <= v_now;

  return query
  with eligible as (
    select
      j.id,
      j.priority,
      j.available_at,
      j.created_at,
      row_number() over (
        partition by coalesce(d.rate_limit_group, 'destination:' || d.key)
        order by j.priority desc, j.available_at, j.created_at
      ) as gate_rank
    from public.social_publication_jobs j
    join public.social_destinations d
      on d.key = j.destination_key
    left join public.social_rate_limit_groups g
      on g.key = d.rate_limit_group
    where j.status in ('queued', 'retry')
      and j.available_at <= v_now
      and j.attempt_count < j.max_attempts
      and d.enabled
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
    from public.social_publication_jobs j
    join eligible e on e.id = j.id
    where e.gate_rank = 1
    order by e.priority desc, e.available_at, e.created_at
    for update of j skip locked
    limit v_limit
  ),
  claimed as (
    update public.social_publication_jobs j
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
    update public.social_destinations d
    set last_claimed_at = v_now
    where d.key in (select c.destination_key from claimed c)
    returning d.key, d.rate_limit_group
  ),
  touched_groups as (
    update public.social_rate_limit_groups g
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
    p.event_id,
    p.payload,
    c.attempt_count,
    c.max_attempts,
    c.provider_progress
  from claimed c
  join public.social_destinations d
    on d.key = c.destination_key
  join public.event_social_publications p
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
begin
  update public.social_publication_jobs j
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
  returning j.publication_id into v_publication_id;

  if not found then
    return false;
  end if;

  perform private.refresh_event_social_publication_status(v_publication_id);
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
  from public.social_publication_jobs j
  where j.id = p_job_id
    and j.status = 'leased'
    and j.lease_owner = p_worker
  for update;

  if not found then
    return false;
  end if;

  update public.social_publication_jobs j
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
  from public.social_destinations d
  where d.key = v_destination_key;

  if v_status = 'retry' then
    update public.social_destinations
    set cooldown_until = greatest(
          coalesce(cooldown_until, '-infinity'::timestamptz),
          now() + make_interval(secs => v_retry_seconds)
        ),
        last_error = left(coalesce(p_error, 'Unknown provider error'), 4000)
    where key = v_destination_key;

    if v_rate_limit_group is not null then
      update public.social_rate_limit_groups
      set cooldown_until = greatest(
            coalesce(cooldown_until, '-infinity'::timestamptz),
            now() + make_interval(secs => v_retry_seconds)
          )
      where key = v_rate_limit_group;
    end if;
  end if;

  perform private.refresh_event_social_publication_status(v_publication_id);
  return true;
end;
$function$;

revoke all on function public.social_mark_publication_failure(
  uuid, text, text, integer, jsonb, boolean
) from public, anon, authenticated;
grant execute on function public.social_mark_publication_failure(
  uuid, text, text, integer, jsonb, boolean
) to service_role;
