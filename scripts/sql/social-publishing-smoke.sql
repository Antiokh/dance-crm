\set ON_ERROR_STOP on

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists auth;
create schema if not exists private;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end
$$;

create type public.app_role as enum ('administrator', 'trainer');
create type public.event_rsvp_response as enum ('going', 'not_going');

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select '00000000-0000-0000-0000-000000000001'::uuid
$$;

create or replace function private.current_dancer_id()
returns uuid
language sql
stable
security definer
as $$
  select '10000000-0000-0000-0000-000000000001'::uuid
$$;

create or replace function private.has_app_role(public.app_role)
returns boolean
language sql
stable
security definer
as $$
  select true
$$;

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

grant usage on schema extensions, auth, private
  to authenticated, service_role;
grant execute on all functions in schema extensions, auth, private
  to authenticated, service_role;

create table public.venues (
  id uuid primary key,
  name text not null,
  address text,
  latitude double precision,
  longitude double precision
);

create table public.l_dance_style (
  id smallint primary key,
  title_en text,
  title_ru text,
  title_sr text,
  is_partner_dance boolean not null default false
);

create table public.dancer (
  id uuid primary key,
  custom_name text,
  first_name text,
  last_name text,
  telegram_username text
);

create table public.dance_events (
  id uuid primary key,
  event_type text not null,
  title text not null,
  description text,
  announcement_image_url text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  venue_id uuid references public.venues(id),
  style_id smallint references public.l_dance_style(id),
  published boolean not null default false,
  cancelled_at timestamptz,
  leader_going_count integer not null default 0,
  follower_going_count integer not null default 0,
  other_going_count integer not null default 0
);

create table public.event_attendance (
  event_id uuid not null references public.dance_events(id),
  dancer_id uuid not null references public.dancer(id),
  response public.event_rsvp_response not null default 'going',
  role_id smallint,
  responded_at timestamptz not null default now(),
  cancelled_at timestamptz,
  primary key (event_id, dancer_id)
);

alter table public.event_attendance enable row level security;
grant select on public.dance_events, public.event_attendance to authenticated;
create policy event_attendance_self on public.event_attendance
for select to authenticated
using (dancer_id = private.current_dancer_id());

insert into public.venues(id, name)
values ('20000000-0000-0000-0000-000000000001', 'Smoke venue');

insert into public.l_dance_style(id, title_en, is_partner_dance)
values (1, 'Smoke style', true);

insert into public.dancer(id, custom_name)
values ('10000000-0000-0000-0000-000000000001', 'Smoke dancer');

insert into public.dance_events(
  id,
  event_type,
  title,
  starts_at,
  ends_at,
  venue_id,
  style_id,
  published
)
values (
  '30000000-0000-0000-0000-000000000001',
  'social',
  'Smoke event',
  now() + interval '1 day',
  now() + interval '1 day 2 hours',
  '20000000-0000-0000-0000-000000000001',
  1,
  true
);

\ir ../../supabase/migrations/20260927133000_social_command_queue.sql
\ir ../../supabase/migrations/20260927134000_event_social_publications.sql

do $$
begin
  if to_regclass('public.social_destinations') is not null then
    raise exception 'publisher destination storage leaked into public';
  end if;
  if to_regclass('public.social_publication_jobs') is not null then
    raise exception 'publisher job storage leaked into public';
  end if;
  if to_regclass('social.destinations') is null
    or to_regclass('social.publications') is null
    or to_regclass('social.delivery_jobs') is null
  then
    raise exception 'private publisher tables are missing';
  end if;
  if has_schema_privilege('authenticated', 'social', 'USAGE') then
    raise exception 'authenticated unexpectedly has USAGE on social';
  end if;
end
$$;

set role authenticated;
select public.enqueue_social_command(
  'social.publish',
  'event',
  '30000000-0000-0000-0000-000000000001',
  'announcement',
  '{}'::jsonb,
  300
);
reset role;

update social.destinations
set enabled = true
where key = 'telegram';

set role service_role;

create temporary table smoke_claimed as
select *
from public.social_claim_commands('smoke:command', 1, 120);

do $$
declare
  v_command uuid;
begin
  select command_id into v_command from smoke_claimed limit 1;
  if v_command is null then
    raise exception 'command worker did not claim the queued command';
  end if;

  perform public.social_process_command(v_command, 'smoke:command');
end
$$;

do $$
begin
  if not exists (
    select 1
    from social.publications p
    where p.source_type = 'event'
      and p.source_id = '30000000-0000-0000-0000-000000000001'::uuid
      and p.publication_type = 'announcement'
  ) then
    raise exception 'command did not materialize a private publication';
  end if;

  if not exists (
    select 1
    from social.delivery_jobs j
    join social.publications p on p.id = j.publication_id
    where p.source_id = '30000000-0000-0000-0000-000000000001'::uuid
      and j.destination_key = 'telegram'
  ) then
    raise exception 'publication did not schedule a private delivery job';
  end if;
end
$$;

create temporary table smoke_jobs as
select *
from public.social_claim_publication_jobs('smoke:delivery', 8, 120);

do $$
declare
  v_job uuid;
begin
  select job_id into v_job from smoke_jobs limit 1;
  if v_job is null then
    raise exception 'delivery worker did not claim the Telegram job';
  end if;

  if not public.social_mark_publication_success(
    v_job,
    'smoke:delivery',
    '123',
    'https://example.test/post/123',
    '{}'::jsonb
  ) then
    raise exception 'delivery job could not be marked successful';
  end if;
end
$$;

reset role;

do $$
begin
  if not exists (
    select 1
    from social.publications p
    where p.source_id = '30000000-0000-0000-0000-000000000001'::uuid
      and p.status = 'published'
      and p.completed_at is not null
  ) then
    raise exception 'publication status was not finalized';
  end if;
end
$$;

select 'social publishing smoke: ok' as result;
