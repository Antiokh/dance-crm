-- Explicit event RSVP state with a role snapshot and cached Leader/Follower balance.
-- Existing quick-attend keeps its old semantics: true = going, false = no response.

do $$
begin
  create type public.event_rsvp_response as enum ('going', 'not_going');
exception
  when duplicate_object then null;
end
$$;

alter table public.event_attendance
  add column if not exists response public.event_rsvp_response not null default 'going',
  add column if not exists role_id smallint references public.l_dance_role(id) on delete set null,
  add column if not exists responded_at timestamptz;

update public.event_attendance
set responded_at = coalesce(responded_at, updated_at, created_at)
where cancelled_at is null
  and responded_at is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'event_attendance_response_role_check'
      and conrelid = 'public.event_attendance'::regclass
  ) then
    alter table public.event_attendance
      add constraint event_attendance_response_role_check
      check (response = 'going'::public.event_rsvp_response or role_id is null);
  end if;
end
$$;

create index if not exists event_attendance_going_role_idx
  on public.event_attendance (event_id, role_id)
  where cancelled_at is null
    and response = 'going'::public.event_rsvp_response;

alter table public.dance_events
  add column if not exists leader_going_count integer not null default 0,
  add column if not exists follower_going_count integer not null default 0,
  add column if not exists other_going_count integer not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'dance_events_going_counts_nonnegative'
      and conrelid = 'public.dance_events'::regclass
  ) then
    alter table public.dance_events
      add constraint dance_events_going_counts_nonnegative
      check (
        leader_going_count >= 0
        and follower_going_count >= 0
        and other_going_count >= 0
      );
  end if;
end
$$;

create or replace function private.refresh_event_rsvp_balance(
  p_event_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_leaders integer;
  v_followers integer;
  v_other integer;
begin
  if p_event_id is null then
    return;
  end if;

  select
    count(*) filter (where ea.role_id = 1)::integer,
    count(*) filter (where ea.role_id = 2)::integer,
    count(*) filter (where ea.role_id is null or ea.role_id not in (1, 2))::integer
  into v_leaders, v_followers, v_other
  from public.event_attendance ea
  where ea.event_id = p_event_id
    and ea.cancelled_at is null
    and ea.response = 'going'::public.event_rsvp_response;

  update public.dance_events
  set leader_going_count = coalesce(v_leaders, 0),
      follower_going_count = coalesce(v_followers, 0),
      other_going_count = coalesce(v_other, 0)
  where id = p_event_id;
end;
$function$;

revoke all on function private.refresh_event_rsvp_balance(uuid)
  from public, anon, authenticated;

create or replace function private.event_attendance_refresh_balance_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.refresh_event_rsvp_balance(
    case when tg_op = 'DELETE' then old.event_id else new.event_id end
  );

  if tg_op = 'UPDATE' and old.event_id is distinct from new.event_id then
    perform private.refresh_event_rsvp_balance(old.event_id);
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

revoke all on function private.event_attendance_refresh_balance_trigger()
  from public, anon, authenticated;

drop trigger if exists event_attendance_refresh_balance
  on public.event_attendance;

create trigger event_attendance_refresh_balance
after insert or delete or update of response, role_id, cancelled_at, event_id
on public.event_attendance
for each row execute function private.event_attendance_refresh_balance_trigger();

do $$
declare
  v_event record;
begin
  for v_event in select id from public.dance_events loop
    perform private.refresh_event_rsvp_balance(v_event.id);
  end loop;
end
$$;

create or replace function public.get_my_event_rsvp(
  p_event_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select jsonb_build_object(
    'event_id', e.id,
    'response', ea.response,
    'role_id', ea.role_id,
    'responded_at', ea.responded_at,
    'leader_going_count', e.leader_going_count,
    'follower_going_count', e.follower_going_count,
    'other_going_count', e.other_going_count,
    'going_count',
      e.leader_going_count + e.follower_going_count + e.other_going_count,
    'role_balance', e.leader_going_count - e.follower_going_count
  )
  from public.dance_events e
  left join public.event_attendance ea
    on ea.event_id = e.id
   and ea.dancer_id = private.current_dancer_id()
   and ea.cancelled_at is null
  where e.id = p_event_id
$function$;

revoke all on function public.get_my_event_rsvp(uuid)
  from public, anon;
grant execute on function public.get_my_event_rsvp(uuid)
  to authenticated;

create or replace function public.set_my_event_response(
  p_event_id uuid,
  p_response public.event_rsvp_response
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_style_id smallint;
  v_is_partner boolean;
  v_role_id smallint;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  if p_response is null then
    raise exception 'response is required' using errcode = '22023';
  end if;

  select e.style_id, s.is_partner_dance
  into v_style_id, v_is_partner
  from public.dance_events e
  left join public.l_dance_style s
    on s.id = e.style_id
  where e.id = p_event_id
    and e.published
    and e.cancelled_at is null
    and coalesce(e.ends_at, e.starts_at) > now();

  if not found then
    raise exception 'event is not available for RSVP'
      using errcode = '23514';
  end if;

  if p_response = 'going'::public.event_rsvp_response
    and v_style_id is not null
    and coalesce(v_is_partner, false)
  then
    v_role_id := private.default_dance_role_for_style(
      v_dancer_id,
      v_style_id
    );
  else
    v_role_id := null;
  end if;

  insert into public.event_attendance (
    event_id,
    dancer_id,
    response,
    role_id,
    cancelled_at,
    responded_at
  )
  values (
    p_event_id,
    v_dancer_id,
    p_response,
    v_role_id,
    null,
    now()
  )
  on conflict (event_id, dancer_id)
  do update
    set response = excluded.response,
        role_id = excluded.role_id,
        cancelled_at = null,
        responded_at = excluded.responded_at,
        updated_at = now();

  return public.get_my_event_rsvp(p_event_id);
end;
$function$;

revoke all on function public.set_my_event_response(
  uuid,
  public.event_rsvp_response
) from public, anon;
grant execute on function public.set_my_event_response(
  uuid,
  public.event_rsvp_response
) to authenticated;

create or replace function public.get_my_event_attendance()
returns table(event_id uuid)
language sql
stable
security invoker
set search_path = ''
as $function$
  select ea.event_id
  from public.event_attendance ea
  where ea.dancer_id = private.current_dancer_id()
    and ea.cancelled_at is null
    and ea.response = 'going'::public.event_rsvp_response
  order by ea.event_id
$function$;

create or replace function public.set_my_event_attending(
  p_event_id uuid,
  p_attending boolean
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode = 'P0002';
  end if;

  if p_attending is null then
    raise exception 'attending flag is required' using errcode = '22023';
  end if;

  if p_attending then
    perform public.set_my_event_response(
      p_event_id,
      'going'::public.event_rsvp_response
    );
    return true;
  end if;

  update public.event_attendance
  set cancelled_at = now(),
      responded_at = now(),
      role_id = null,
      updated_at = now()
  where event_id = p_event_id
    and dancer_id = v_dancer_id
    and cancelled_at is null;

  return false;
end;
$function$;
