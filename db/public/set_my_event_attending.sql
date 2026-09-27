-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: set_my_event_attending
-- Updated:  2026-09-27T01:01:02.383Z

-- overload
-- language: plpgsql
-- args: p_event_id uuid, p_attending boolean
-- returns: boolean

CREATE OR REPLACE FUNCTION public.set_my_event_attending(p_event_id uuid, p_attending boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode='P0002';
  end if;

  if p_attending is null then
    raise exception 'attending flag is required' using errcode='22023';
  end if;

  if p_attending then
    if not exists (
      select 1
      from public.dance_events e
      where e.id = p_event_id
        and e.published
        and e.cancelled_at is null
        and coalesce(e.ends_at, e.starts_at) > now()
    ) then
      raise exception 'event is not available for RSVP'
        using errcode='23514';
    end if;

    insert into public.event_attendance (
      event_id,
      dancer_id,
      cancelled_at
    )
    values (
      p_event_id,
      v_dancer_id,
      null
    )
    on conflict (event_id, dancer_id)
    do update
      set cancelled_at = null,
          updated_at = now();

    return true;
  end if;

  update public.event_attendance
  set cancelled_at = now(),
      updated_at = now()
  where event_id = p_event_id
    and dancer_id = v_dancer_id
    and cancelled_at is null;

  return false;
end;
$function$
