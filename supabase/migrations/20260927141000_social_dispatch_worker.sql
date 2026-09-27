-- Worker authentication and environment-safe pg_cron dispatch.
-- The cron exists in every environment but remains inert until an administrator
-- configures that environment's own Edge Function URL.

create extension if not exists supabase_vault with schema vault;

do $$
begin
  if not exists (
    select 1
    from vault.secrets
    where name = 'dance_social_dispatch_secret'
  ) then
    perform vault.create_secret(
      extensions.gen_random_uuid()::text
        || extensions.gen_random_uuid()::text,
      'dance_social_dispatch_secret',
      'Shared secret for dance-crm social-publish-dispatch cron calls'
    );
  end if;
end
$$;

create table if not exists public.social_dispatch_config (
  singleton boolean primary key default true check (singleton),
  dispatch_url text,
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.dancer(id) on delete set null
);

insert into public.social_dispatch_config (singleton)
values (true)
on conflict (singleton) do nothing;

drop trigger if exists social_dispatch_config_touch_updated_at
  on public.social_dispatch_config;
create trigger social_dispatch_config_touch_updated_at
before update on public.social_dispatch_config
for each row execute function private.touch_updated_at();

alter table public.social_dispatch_config enable row level security;
revoke all on public.social_dispatch_config from anon, authenticated;
grant all on public.social_dispatch_config to service_role;

create or replace function public.social_get_dispatch_secret()
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select ds.decrypted_secret
  from vault.decrypted_secrets ds
  where ds.name = 'dance_social_dispatch_secret'
  order by ds.created_at desc
  limit 1
$function$;

revoke all on function public.social_get_dispatch_secret()
  from public, anon, authenticated;
grant execute on function public.social_get_dispatch_secret()
  to service_role;

create or replace function public.admin_configure_social_dispatch(
  p_dispatch_url text,
  p_enabled boolean default true
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_url text := nullif(btrim(p_dispatch_url), '');
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode = '42501';
  end if;

  if p_enabled and v_url is null then
    raise exception 'dispatch URL is required when enabling social dispatch'
      using errcode = '22023';
  end if;

  if v_url is not null
    and (
      v_url !~ '^https://'
      or v_url !~ '/functions/v1/social-publish-dispatch/?$'
    )
  then
    raise exception 'invalid social dispatch URL'
      using errcode = '22023';
  end if;

  update public.social_dispatch_config
  set dispatch_url = v_url,
      enabled = coalesce(p_enabled, false),
      updated_by = private.current_dancer_id()
  where singleton;

  return jsonb_build_object(
    'dispatch_url', v_url,
    'enabled', coalesce(p_enabled, false)
  );
end;
$function$;

revoke all on function public.admin_configure_social_dispatch(text, boolean)
  from public, anon;
grant execute on function public.admin_configure_social_dispatch(text, boolean)
  to authenticated;

create or replace function public.social_dispatch_tick()
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
  select c.dispatch_url
  into v_url
  from public.social_dispatch_config c
  where c.singleton
    and c.enabled;

  if v_url is null then
    return null;
  end if;

  select ds.decrypted_secret
  into v_secret
  from vault.decrypted_secrets ds
  where ds.name = 'dance_social_dispatch_secret'
  order by ds.created_at desc
  limit 1;

  if v_secret is null or v_secret = '' then
    raise exception 'dance social dispatch secret is missing';
  end if;

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-dance-social-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  )
  into v_request_id;

  return v_request_id;
end;
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
    where jobname = 'dance-social-publish-dispatch'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;

  perform cron.schedule(
    'dance-social-publish-dispatch',
    '* * * * *',
    'select public.social_dispatch_tick();'
  );
end
$$;
