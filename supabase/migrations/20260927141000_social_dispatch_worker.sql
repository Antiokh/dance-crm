-- Worker authentication and environment-safe pg_cron dispatch.
-- Both workers remain inert until an administrator configures this environment's
-- own Edge Function URLs. Publisher state stays in the non-exposed social schema.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$
begin
  if not exists (
    select 1
    from vault.secrets
    where name = 'social_worker_secret'
  ) then
    perform vault.create_secret(
      extensions.gen_random_uuid()::text
        || extensions.gen_random_uuid()::text,
      'social_worker_secret',
      'Shared secret for social command/delivery worker cron calls',
      null
    );
  end if;
end
$$;

create table if not exists social.worker_config (
  singleton boolean primary key default true check (singleton),
  command_url text,
  dispatch_url text,
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

insert into social.worker_config (singleton)
values (true)
on conflict (singleton) do nothing;

drop trigger if exists social_worker_config_touch_updated_at
  on social.worker_config;
create trigger social_worker_config_touch_updated_at
before update on social.worker_config
for each row execute function private.touch_updated_at();

alter table social.worker_config enable row level security;
revoke all on social.worker_config from public, anon, authenticated;
grant all on social.worker_config to service_role;

create or replace function public.social_get_worker_secret()
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select ds.decrypted_secret
  from vault.decrypted_secrets ds
  where ds.name = 'social_worker_secret'
  order by ds.created_at desc
  limit 1
$function$;

revoke all on function public.social_get_worker_secret()
  from public, anon, authenticated;
grant execute on function public.social_get_worker_secret()
  to service_role;

create or replace function public.admin_configure_social_workers(
  p_command_url text,
  p_dispatch_url text,
  p_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_command_url text := nullif(btrim(p_command_url), '');
  v_dispatch_url text := nullif(btrim(p_dispatch_url), '');
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode = '42501';
  end if;

  if p_enabled and (v_command_url is null or v_dispatch_url is null) then
    raise exception 'both social worker URLs are required when enabling'
      using errcode = '22023';
  end if;

  if v_command_url is not null
    and (
      v_command_url !~ '^https://'
      or v_command_url !~ '/functions/v1/social-command-worker/?$'
    )
  then
    raise exception 'invalid social command worker URL'
      using errcode = '22023';
  end if;

  if v_dispatch_url is not null
    and (
      v_dispatch_url !~ '^https://'
      or v_dispatch_url !~ '/functions/v1/social-publish-dispatch/?$'
    )
  then
    raise exception 'invalid social delivery dispatcher URL'
      using errcode = '22023';
  end if;

  update social.worker_config
  set command_url = v_command_url,
      dispatch_url = v_dispatch_url,
      enabled = coalesce(p_enabled, false),
      updated_by = private.current_dancer_id()
  where singleton;

  return jsonb_build_object(
    'command_url', v_command_url,
    'dispatch_url', v_dispatch_url,
    'enabled', coalesce(p_enabled, false)
  );
end;
$function$;

revoke all on function public.admin_configure_social_workers(
  text, text, boolean
) from public, anon;
grant execute on function public.admin_configure_social_workers(
  text, text, boolean
) to authenticated;

create or replace function private.social_worker_tick(
  p_worker_kind text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_url text;
  v_secret text;
  v_request_id bigint;
begin
  if p_worker_kind not in ('command', 'dispatch') then
    raise exception 'invalid social worker kind'
      using errcode = '22023';
  end if;

  select case
      when p_worker_kind = 'command' then c.command_url
      else c.dispatch_url
    end
  into v_url
  from social.worker_config c
  where c.singleton
    and c.enabled;

  if v_url is null then
    return null;
  end if;

  select ds.decrypted_secret
  into v_secret
  from vault.decrypted_secrets ds
  where ds.name = 'social_worker_secret'
  order by ds.created_at desc
  limit 1;

  if v_secret is null or v_secret = '' then
    raise exception 'social worker secret is missing';
  end if;

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-social-worker-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  )
  into v_request_id;

  return v_request_id;
end;
$function$;

revoke all on function private.social_worker_tick(text)
  from public, anon, authenticated;

create or replace function public.social_command_tick()
returns bigint
language sql
security definer
set search_path = ''
as $function$
  select private.social_worker_tick('command')
$function$;

revoke all on function public.social_command_tick()
  from public, anon, authenticated;
grant execute on function public.social_command_tick()
  to service_role;

create or replace function public.social_dispatch_tick()
returns bigint
language sql
security definer
set search_path = ''
as $function$
  select private.social_worker_tick('dispatch')
$function$;

revoke all on function public.social_dispatch_tick()
  from public, anon, authenticated;
grant execute on function public.social_dispatch_tick()
  to service_role;

do $$
declare
  v_job record;
begin
  for v_job in
    select jobid
    from cron.job
    where jobname in (
      'social-command-worker',
      'social-publish-dispatch'
    )
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;

  perform cron.schedule(
    'social-command-worker',
    '* * * * *',
    'select public.social_command_tick();'
  );

  perform cron.schedule(
    'social-publish-dispatch',
    '* * * * *',
    'select public.social_dispatch_tick();'
  );
end
$$;
