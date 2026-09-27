create or replace function private.review_overbook_request_internal(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null::text
)
returns public.overbook_requests
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.overbook_requests%rowtype;
  v_reviewer uuid := private.current_dancer_id();
begin
  if v_reviewer is null then
    raise exception 'dancer profile not found' using errcode='P0002';
  end if;

  if p_approve is null then
    raise exception 'approval decision is required' using errcode='22023';
  end if;

  select *
  into v_request
  from public.overbook_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'overbook request not found' using errcode='P0002';
  end if;

  if not private.can_operate_slot(v_request.slot_id) then
    raise exception 'trainer or administrator role required'
      using errcode='42501';
  end if;

  if v_request.status <> 'pending'::public.overbook_request_status then
    raise exception 'overbook request is not pending'
      using errcode='23514';
  end if;

  if p_approve then
    update public.bookings b
    set status = 'booked'::public.booking_status
    where b.id = v_request.booking_id
      and b.status = 'waitlisted'::public.booking_status;

    if not found then
      raise exception 'booking is no longer waitlisted'
        using errcode='23514';
    end if;

    update public.overbook_requests
    set status = 'approved'::public.overbook_request_status,
        reviewed_at = now(),
        reviewed_by = v_reviewer,
        review_note = nullif(btrim(p_note), '')
    where id = p_request_id
    returning * into v_request;
  else
    update public.overbook_requests
    set status = 'rejected'::public.overbook_request_status,
        reviewed_at = now(),
        reviewed_by = v_reviewer,
        review_note = nullif(btrim(p_note), '')
    where id = p_request_id
    returning * into v_request;
  end if;

  return v_request;
end;
$function$;

revoke all on function private.review_overbook_request_internal(uuid, boolean, text)
  from public;
revoke all on function private.review_overbook_request_internal(uuid, boolean, text)
  from anon;
revoke all on function private.review_overbook_request_internal(uuid, boolean, text)
  from authenticated;

create or replace function public.review_overbook_request(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null::text
)
returns public.overbook_requests
language sql
security invoker
set search_path = ''
as $function$
  select private.review_overbook_request_internal(
    p_request_id,
    p_approve,
    p_note
  )
$function$;
