-- Dance CRM consumer adapter for the reusable private social publishing core.
-- Domain triggers enqueue public commands. The system command worker materializes
-- event snapshots/publications and delivery jobs through this adapter.

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
    'balance', jsonb_build_object(
      'leader', e.leader_going_count,
      'follower', e.follower_going_count,
      'other', e.other_going_count,
      'total',
        e.leader_going_count
        + e.follower_going_count
        + e.other_going_count
    ),
    'attendees', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'name', coalesce(
            nullif(btrim(d.custom_name), ''),
            nullif(btrim(concat_ws(' ', d.first_name, d.last_name)), ''),
            case
              when nullif(btrim(d.telegram_username), '') is not null
                then '@' || btrim(d.telegram_username)
              else null
            end,
            'Танцор'
          ),
          'role_id', ea.role_id,
          'responded_at', ea.responded_at
        )
        order by
          case ea.role_id when 1 then 1 when 2 then 2 else 3 end,
          coalesce(
            nullif(btrim(d.custom_name), ''),
            nullif(btrim(concat_ws(' ', d.first_name, d.last_name)), ''),
            nullif(btrim(d.telegram_username), ''),
            'Танцор'
          )
      )
      from public.event_attendance ea
      join public.dancer d on d.id = ea.dancer_id
      where ea.event_id = e.id
        and ea.cancelled_at is null
        and ea.response = 'going'::public.event_rsvp_response
    ), '[]'::jsonb),
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

create or replace function private.schedule_event_social_jobs(
  p_publication_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_publication social.publications%rowtype;
  v_inserted integer := 0;
begin
  select *
  into v_publication
  from social.publications p
  where p.id = p_publication_id;

  if not found then
    raise exception 'social publication not found' using errcode = 'P0002';
  end if;

  insert into social.delivery_jobs (
    publication_id,
    destination_key,
    operation,
    lane,
    expires_at,
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
    'transactional',
    case
      when v_publication.publication_type = 'rsvp_update'
        then nullif(v_publication.payload->>'ends_at', '')::timestamptz
      else null
    end,
    v_publication.id::text || ':' || d.key,
    case
      when v_publication.publication_type = 'cancelled' then 400
      when v_publication.publication_type in ('announcement', 'updated') then 300
      when v_publication.publication_type = 'rsvp_update' then 200
      else 100
    end,
    d.max_attempts
  from social.destinations d
  where d.enabled
    and v_publication.source_type = 'event'
    and (
      v_publication.publication_type <> 'rsvp_update'
      or d.publisher = 'telegram_api'
    )
    and (
      v_publication.publication_type <> 'cancelled'
      or exists (
        select 1
        from social.delivery_jobs prior_job
        join social.publications prior_publication
          on prior_publication.id = prior_job.publication_id
        where prior_publication.source_type = v_publication.source_type
          and prior_publication.source_id = v_publication.source_id
          and prior_publication.id <> v_publication.id
          and prior_job.destination_key = d.key
          and prior_job.status = 'published'
      )
    )
  on conflict (publication_id, destination_key) do nothing;

  get diagnostics v_inserted = row_count;

  perform private.refresh_social_publication_status(v_publication.id);
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
      from social.publications p
      where p.source_type = 'event'
        and p.source_id = p_event_id
        and p.publication_type = 'rsvp_update'
        and p.status in ('queued', 'held', 'partial')
      order by p.version desc
    loop
      update social.delivery_jobs j
      set status = 'cancelled',
          lease_owner = null,
          lease_expires_at = null,
          last_error = 'Superseded by newer RSVP state'
      where j.publication_id = v_old_publication_id
        and j.status in ('queued', 'retry');

      perform private.refresh_social_publication_status(v_old_publication_id);
    end loop;
  else
    for v_old_publication_id in
      select p.id
      from social.publications p
      where p.source_type = 'event'
        and p.source_id = p_event_id
        and p.publication_type <> 'rsvp_update'
        and p.status in ('queued', 'held', 'partial')
      order by p.version desc
    loop
      update social.delivery_jobs j
      set status = 'cancelled',
          lease_owner = null,
          lease_expires_at = null,
          last_error = 'Superseded by newer event publication'
      where j.publication_id = v_old_publication_id
        and j.status in ('queued', 'retry');

      perform private.refresh_social_publication_status(v_old_publication_id);
    end loop;
  end if;

  select coalesce(max(p.version), 0) + 1
  into v_version
  from social.publications p
  where p.source_type = 'event'
    and p.source_id = p_event_id;

  v_payload := private.event_social_payload(p_event_id);

  insert into social.publications (
    source_type,
    source_id,
    publication_type,
    version,
    transaction_id,
    payload
  )
  values (
    'event',
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
  uuid, text, bigint
) from public, anon, authenticated;

create or replace function private.event_social_change_trigger()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_command_type text;
  v_operation text;
  v_priority integer := 300;
begin
  if tg_op = 'INSERT' then
    if new.published and new.cancelled_at is null then
      perform public.enqueue_social_command(
        'social.publish',
        'event',
        new.id,
        'announcement',
        jsonb_build_object('transaction_id', txid_current()),
        300
      );
    end if;
    return new;
  end if;

  if old.published and not new.published then
    perform public.enqueue_social_command(
      'social.unpublish',
      'event',
      new.id,
      'unpublished',
      jsonb_build_object('transaction_id', txid_current()),
      400
    );
    return new;
  end if;

  if old.cancelled_at is null and new.cancelled_at is not null
    and (old.published or new.published)
  then
    v_command_type := 'social.cancel';
    v_operation := 'cancelled';
    v_priority := 400;
  elsif old.cancelled_at is not null
    and new.cancelled_at is null
    and new.published
  then
    v_command_type := 'social.update';
    v_operation := 'updated';
  elsif not old.published and new.published
    and new.cancelled_at is null
  then
    v_command_type := 'social.publish';
    v_operation := 'announcement';
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
    v_command_type := 'social.update';
    v_operation := 'updated';
  end if;

  if v_command_type is not null then
    perform public.enqueue_social_command(
      v_command_type,
      'event',
      new.id,
      v_operation,
      jsonb_build_object('transaction_id', txid_current()),
      v_priority
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
security invoker
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
      perform public.enqueue_social_command(
        'social.rsvp_update',
        'event',
        v_event_id,
        'rsvp_update',
        jsonb_build_object('transaction_id', txid_current()),
        200
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
declare
  v_command_type text;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required' using errcode = '42501';
  end if;

  v_command_type := case p_publication_type
    when 'announcement' then 'social.publish'
    when 'updated' then 'social.update'
    when 'cancelled' then 'social.cancel'
    when 'rsvp_update' then 'social.rsvp_update'
    else null
  end;

  if v_command_type is null then
    raise exception 'invalid publication type' using errcode = '22023';
  end if;

  return public.enqueue_social_command(
    v_command_type,
    'event',
    p_event_id,
    p_publication_type,
    '{}'::jsonb,
    case when p_publication_type = 'cancelled' then 400 else 300 end
  );
end;
$function$;

revoke all on function public.admin_queue_event_social_publication(uuid, text)
  from public, anon;
grant execute on function public.admin_queue_event_social_publication(uuid, text)
  to authenticated;

create or replace function public.social_process_command(
  p_command_id uuid,
  p_worker text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_command public.social_commands%rowtype;
  v_publication_type text;
  v_publication_id uuid;
  v_publication uuid;
begin
  select *
  into v_command
  from public.social_commands c
  where c.id = p_command_id
    and c.status = 'leased'
    and c.lease_owner = p_worker
    and c.lease_expires_at > now()
  for update;

  if not found then
    raise exception 'leased social command not found' using errcode = 'P0002';
  end if;

  if v_command.source_type <> 'event' then
    raise exception 'unsupported social source type: %', v_command.source_type
      using errcode = '22023';
  end if;

  if v_command.command_type = 'social.unpublish' then
    update social.delivery_jobs j
    set status = 'cancelled',
        lease_owner = null,
        lease_expires_at = null,
        last_error = 'Source was unpublished before delivery'
    where j.publication_id in (
      select p.id
      from social.publications p
      where p.source_type = v_command.source_type
        and p.source_id = v_command.source_id
    )
      and j.status in ('queued', 'retry');

    for v_publication in
      select p.id
      from social.publications p
      where p.source_type = v_command.source_type
        and p.source_id = v_command.source_id
        and p.status in ('queued', 'held', 'partial')
    loop
      perform private.refresh_social_publication_status(v_publication);
    end loop;
  else
    v_publication_type := case v_command.operation
      when 'announcement' then 'announcement'
      when 'updated' then 'updated'
      when 'cancelled' then 'cancelled'
      when 'rsvp_update' then 'rsvp_update'
      else null
    end;

    if v_publication_type is null then
      raise exception 'unsupported event social operation: %', v_command.operation
        using errcode = '22023';
    end if;

    v_publication_id := private.queue_event_social_publication(
      v_command.source_id,
      v_publication_type,
      coalesce((v_command.payload->>'transaction_id')::bigint, txid_current())
    );
  end if;

  update public.social_commands c
  set status = 'processed',
      processed_at = now(),
      lease_owner = null,
      lease_expires_at = null,
      last_error = null
  where c.id = v_command.id;

  return jsonb_build_object(
    'command_id', v_command.id,
    'publication_id', v_publication_id,
    'source_type', v_command.source_type,
    'source_id', v_command.source_id,
    'operation', v_command.operation
  );
end;
$function$;

revoke all on function public.social_process_command(uuid, text)
  from public, anon, authenticated;
grant execute on function public.social_process_command(uuid, text)
  to service_role;

