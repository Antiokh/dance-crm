-- Administrative control/diagnostics for the private social module.
-- These RPCs expose only safe configuration and operational summaries.

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
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode = '42501';
  end if;

  return public.social_configure_workers(
    p_command_url,
    p_dispatch_url,
    p_enabled,
    private.current_dancer_id()
  );
end;
$function$;

revoke all on function public.admin_configure_social_workers(
  text, text, boolean
) from public, anon;
grant execute on function public.admin_configure_social_workers(
  text, text, boolean
) to authenticated;

create or replace function public.admin_set_social_destination(
  p_key text,
  p_enabled boolean,
  p_settings jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_settings jsonb;
  v_row social.destinations%rowtype;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode = '42501';
  end if;

  if p_key is null or btrim(p_key) = '' then
    raise exception 'destination key is required'
      using errcode = '22023';
  end if;

  v_settings := coalesce(p_settings, '{}'::jsonb);

  if jsonb_typeof(v_settings) <> 'object' then
    raise exception 'destination settings must be a JSON object'
      using errcode = '22023';
  end if;

  if v_settings ?| array[
    'token',
    'access_token',
    'bot_token',
    'secret',
    'password',
    'webhook_url',
    'authorization',
    'api_key'
  ] then
    raise exception 'provider secrets must stay in Edge Function secrets'
      using errcode = '22023';
  end if;

  update social.destinations d
  set enabled = coalesce(p_enabled, false),
      settings = d.settings || v_settings,
      cooldown_until = case
        when coalesce(p_enabled, false) then null
        else d.cooldown_until
      end,
      last_error = case
        when coalesce(p_enabled, false) then null
        else d.last_error
      end
  where d.key = p_key
  returning * into v_row;

  if not found then
    raise exception 'social destination not found'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'key', v_row.key,
    'platform', v_row.platform,
    'publisher', v_row.publisher,
    'display_name', v_row.display_name,
    'enabled', v_row.enabled,
    'rate_limit_group', v_row.rate_limit_group,
    'settings', v_row.settings,
    'cooldown_until', v_row.cooldown_until,
    'last_error', v_row.last_error
  );
end;
$function$;

revoke all on function public.admin_set_social_destination(
  text, boolean, jsonb
) from public, anon;
grant execute on function public.admin_set_social_destination(
  text, boolean, jsonb
) to authenticated;

create or replace function public.admin_get_social_delivery_status(
  p_event_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_destinations jsonb;
  v_workers jsonb;
  v_commands jsonb;
  v_publications jsonb;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', d.key,
        'platform', d.platform,
        'publisher', d.publisher,
        'display_name', d.display_name,
        'enabled', d.enabled,
        'rate_limit_group', d.rate_limit_group,
        'settings', d.settings,
        'last_claimed_at', d.last_claimed_at,
        'cooldown_until', d.cooldown_until,
        'last_error', d.last_error
      )
      order by d.key
    ),
    '[]'::jsonb
  )
  into v_destinations
  from social.destinations d;

  select coalesce(
    jsonb_build_object(
      'enabled', c.enabled,
      'command_url', c.command_url,
      'dispatch_url', c.dispatch_url,
      'updated_at', c.updated_at
    ),
    jsonb_build_object(
      'enabled', false,
      'command_url', null,
      'dispatch_url', null,
      'updated_at', null
    )
  )
  into v_workers
  from social.worker_config c
  where c.singleton;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'command_id', c.id,
        'command_type', c.command_type,
        'source_type', c.source_type,
        'source_id', c.source_id,
        'operation', c.operation,
        'status', c.status,
        'attempt_count', c.attempt_count,
        'available_at', c.available_at,
        'last_error', c.last_error,
        'created_at', c.created_at,
        'processed_at', c.processed_at
      )
      order by c.created_at desc
    ),
    '[]'::jsonb
  )
  into v_commands
  from (
    select c0.*
    from public.social_commands c0
    where c0.source_type = 'event'
      and (p_event_id is null or c0.source_id = p_event_id)
    order by c0.created_at desc
    limit 20
  ) c;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'publication_id', p.id,
        'source_type', p.source_type,
        'event_id', p.source_id,
        'publication_type', p.publication_type,
        'version', p.version,
        'status', p.status,
        'created_at', p.created_at,
        'completed_at', p.completed_at,
        'jobs', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'job_id', j.id,
              'destination_key', j.destination_key,
              'operation', j.operation,
              'lane', j.lane,
              'status', j.status,
              'attempt_count', j.attempt_count,
              'available_at', j.available_at,
              'expires_at', j.expires_at,
              'depends_on_job_id', j.depends_on_job_id,
              'external_post_id', j.external_post_id,
              'external_post_url', j.external_post_url,
              'last_error', j.last_error,
              'published_at', j.published_at
            )
            order by j.destination_key
          )
          from social.delivery_jobs j
          where j.publication_id = p.id
        ), '[]'::jsonb)
      )
      order by p.created_at desc
    ),
    '[]'::jsonb
  )
  into v_publications
  from (
    select p0.*
    from social.publications p0
    where p0.source_type = 'event'
      and (p_event_id is null or p0.source_id = p_event_id)
    order by p0.created_at desc
    limit 20
  ) p;

  return jsonb_build_object(
    'workers', v_workers,
    'destinations', v_destinations,
    'commands', v_commands,
    'publications', v_publications
  );
end;
$function$;

revoke all on function public.admin_get_social_delivery_status(uuid)
  from public, anon;
grant execute on function public.admin_get_social_delivery_status(uuid)
  to authenticated;
