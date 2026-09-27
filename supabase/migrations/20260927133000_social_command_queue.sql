-- Durable public command boundary for the private social publishing subsystem.
-- CRM/domain state remains in public and continues to use RLS.
-- Browser/domain code may enqueue intent here, but never writes social.* directly.

create table if not exists public.social_commands (
  id uuid primary key default extensions.gen_random_uuid(),
  command_type text not null check (
    command_type in (
      'social.publish',
      'social.update',
      'social.cancel',
      'social.rsvp_update',
      'social.unpublish'
    )
  ),
  source_type text not null check (btrim(source_type) <> ''),
  source_id uuid not null,
  operation text not null check (btrim(operation) <> ''),
  payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload) = 'object'),
  status text not null default 'queued' check (
    status in ('queued', 'leased', 'retry', 'processed', 'dead', 'cancelled')
  ),
  priority integer not null default 100,
  attempt_count integer not null default 0,
  max_attempts integer not null default 8
    check (max_attempts between 1 and 20),
  available_at timestamptz not null default now(),
  lease_owner text,
  lease_expires_at timestamptz,
  last_error text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists social_commands_ready_idx
  on public.social_commands (
    status,
    available_at,
    priority desc,
    created_at
  );

create index if not exists social_commands_source_idx
  on public.social_commands (
    source_type,
    source_id,
    created_at desc
  );

create index if not exists social_commands_lease_idx
  on public.social_commands (lease_expires_at)
  where status = 'leased';

drop trigger if exists social_commands_touch_updated_at
  on public.social_commands;
create trigger social_commands_touch_updated_at
before update on public.social_commands
for each row execute function private.touch_updated_at();

alter table public.social_commands enable row level security;

revoke all on public.social_commands from anon, authenticated;
grant insert on public.social_commands to authenticated;
grant all on public.social_commands to service_role;

drop policy if exists social_commands_insert_authenticated
  on public.social_commands;
create policy social_commands_insert_authenticated
on public.social_commands
for insert
to authenticated
with check (
  status = 'queued'
  and attempt_count = 0
  and lease_owner is null
  and lease_expires_at is null
  and processed_at is null
  and created_by = auth.uid()
  and source_type = 'event'
  and (
    private.has_app_role('administrator'::public.app_role)
    or (
      command_type = 'social.rsvp_update'
      and operation = 'rsvp_update'
      and exists (
        select 1
        from public.event_attendance ea
        where ea.event_id = source_id
          and ea.dancer_id = private.current_dancer_id()
      )
    )
  )
);

create or replace function public.enqueue_social_command(
  p_command_type text,
  p_source_type text,
  p_source_id uuid,
  p_operation text,
  p_payload jsonb default '{}'::jsonb,
  p_priority integer default 100
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_id uuid := extensions.gen_random_uuid();
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
begin
  if p_command_type not in (
    'social.publish',
    'social.update',
    'social.cancel',
    'social.rsvp_update',
    'social.unpublish'
  ) then
    raise exception 'unsupported social command type'
      using errcode = '22023';
  end if;

  if p_source_type is null or btrim(p_source_type) = '' then
    raise exception 'source type is required'
      using errcode = '22023';
  end if;

  if p_source_id is null then
    raise exception 'source id is required'
      using errcode = '22023';
  end if;

  if p_operation is null or btrim(p_operation) = '' then
    raise exception 'operation is required'
      using errcode = '22023';
  end if;

  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'social command payload must be a JSON object'
      using errcode = '22023';
  end if;

  insert into public.social_commands (
    id,
    command_type,
    source_type,
    source_id,
    operation,
    payload,
    priority,
    created_by
  )
  values (
    v_id,
    p_command_type,
    p_source_type,
    p_source_id,
    p_operation,
    v_payload,
    least(greatest(coalesce(p_priority, 100), 0), 1000),
    auth.uid()
  );

  return v_id;
end;
$function$;

revoke all on function public.enqueue_social_command(
  text, text, uuid, text, jsonb, integer
) from public, anon;
grant execute on function public.enqueue_social_command(
  text, text, uuid, text, jsonb, integer
) to authenticated, service_role;

create or replace function public.social_claim_commands(
  p_worker text,
  p_limit integer default 16,
  p_lease_seconds integer default 90
)
returns table(
  command_id uuid,
  command_type text,
  source_type text,
  source_id uuid,
  operation text,
  payload jsonb,
  attempt_count integer,
  max_attempts integer
)
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_now timestamptz := now();
  v_limit integer := least(greatest(coalesce(p_limit, 16), 1), 64);
  v_lease_seconds integer :=
    least(greatest(coalesce(p_lease_seconds, 90), 30), 600);
begin
  if p_worker is null or btrim(p_worker) = '' then
    raise exception 'worker id required'
      using errcode = '22023';
  end if;

  with ranked_rsvp as (
    select
      c.id,
      row_number() over (
        partition by c.source_type, c.source_id, c.operation
        order by c.created_at desc, c.id desc
      ) as queue_rank
    from public.social_commands c
    where c.status in ('queued', 'retry')
      and c.command_type = 'social.rsvp_update'
      and c.operation = 'rsvp_update'
  )
  update public.social_commands c
  set status = 'cancelled',
      last_error = 'Superseded by newer RSVP command',
      lease_owner = null,
      lease_expires_at = null
  from ranked_rsvp r
  where c.id = r.id
    and r.queue_rank > 1;

  update public.social_commands c
  set status = case
        when c.attempt_count >= c.max_attempts then 'dead'
        else 'retry'
      end,
      available_at = case
        when c.attempt_count >= c.max_attempts
          then c.available_at
        else greatest(c.available_at, v_now + interval '30 seconds')
      end,
      last_error = 'Command worker lease expired',
      lease_owner = null,
      lease_expires_at = null
  where c.status = 'leased'
    and c.lease_expires_at <= v_now;

  return query
  with candidates as (
    select c.id
    from public.social_commands c
    where c.status in ('queued', 'retry')
      and c.available_at <= v_now
      and c.attempt_count < c.max_attempts
    order by c.priority desc, c.available_at, c.created_at
    for update skip locked
    limit v_limit
  ),
  claimed as (
    update public.social_commands c
    set status = 'leased',
        attempt_count = c.attempt_count + 1,
        lease_owner = p_worker,
        lease_expires_at = v_now + make_interval(secs => v_lease_seconds),
        last_error = null
    from candidates x
    where c.id = x.id
    returning c.*
  )
  select
    c.id,
    c.command_type,
    c.source_type,
    c.source_id,
    c.operation,
    c.payload,
    c.attempt_count,
    c.max_attempts
  from claimed c
  order by c.priority desc, c.created_at;
end;
$function$;

revoke all on function public.social_claim_commands(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.social_claim_commands(text, integer, integer)
  to service_role;

create or replace function public.social_mark_command_failure(
  p_command_id uuid,
  p_worker text,
  p_error text,
  p_retry_after_seconds integer default 60,
  p_terminal boolean default false
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_status text;
  v_retry_seconds integer :=
    least(greatest(coalesce(p_retry_after_seconds, 60), 1), 86400);
begin
  select case
      when p_terminal or c.attempt_count >= c.max_attempts
        then 'dead'
      else 'retry'
    end
  into v_status
  from public.social_commands c
  where c.id = p_command_id
    and c.status = 'leased'
    and c.lease_owner = p_worker
    and c.lease_expires_at > now()
  for update;

  if not found then
    return false;
  end if;

  update public.social_commands c
  set status = v_status,
      available_at = case
        when v_status = 'retry'
          then now() + make_interval(secs => v_retry_seconds)
        else c.available_at
      end,
      last_error = left(coalesce(p_error, 'Unknown command worker error'), 4000),
      lease_owner = null,
      lease_expires_at = null
  where c.id = p_command_id;

  return true;
end;
$function$;

revoke all on function public.social_mark_command_failure(
  uuid, text, text, integer, boolean
) from public, anon, authenticated;
grant execute on function public.social_mark_command_failure(
  uuid, text, text, integer, boolean
) to service_role;
