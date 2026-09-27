-- Administrator operations and diagnostics for event social delivery.

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
  v_row public.social_destinations%rowtype;
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
    'webhook_url'
  ] then
    raise exception 'provider secrets must stay in Edge Function secrets'
      using errcode = '22023';
  end if;

  update public.social_destinations d
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
  text,
  boolean,
  jsonb
) from public, anon;
grant execute on function public.admin_set_social_destination(
  text,
  boolean,
  jsonb
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
  v_dispatch jsonb;
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
  from public.social_destinations d;

  select coalesce(
    jsonb_build_object(
      'enabled', c.enabled,
      'dispatch_url', c.dispatch_url,
      'updated_at', c.updated_at
    ),
    jsonb_build_object(
      'enabled', false,
      'dispatch_url', null,
      'updated_at', null
    )
  )
  into v_dispatch
  from public.social_dispatch_config c
  where c.singleton;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'publication_id', p.id,
        'event_id', p.event_id,
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
              'status', j.status,
              'attempt_count', j.attempt_count,
              'available_at', j.available_at,
              'external_post_id', j.external_post_id,
              'external_post_url', j.external_post_url,
              'last_error', j.last_error,
              'published_at', j.published_at
            )
            order by j.destination_key
          )
          from public.social_publication_jobs j
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
    from public.event_social_publications p0
    where p_event_id is null or p0.event_id = p_event_id
    order by p0.created_at desc
    limit 20
  ) p;

  return jsonb_build_object(
    'dispatch', v_dispatch,
    'destinations', v_destinations,
    'publications', v_publications
  );
end;
$function$;

revoke all on function public.admin_get_social_delivery_status(uuid)
  from public, anon;
grant execute on function public.admin_get_social_delivery_status(uuid)
  to authenticated;
