-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: set_my_class_attending
-- Updated:  2026-09-27T00:51:04.201Z

-- overload
-- language: plpgsql
-- args: p_slot_id uuid, p_attending boolean
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.set_my_class_attending(p_slot_id uuid, p_attending boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_dancer_id uuid := private.current_dancer_id();
  v_booking public.bookings%rowtype;
begin
  if v_dancer_id is null then
    raise exception 'dancer profile not found' using errcode='P0002';
  end if;

  if p_attending is null then
    raise exception 'attending flag is required' using errcode='22023';
  end if;

  select *
  into v_booking
  from public.bookings b
  where b.slot_id = p_slot_id
    and b.dancer_id = v_dancer_id
  for update;

  if p_attending then
    if v_booking.id is not null
      and v_booking.status <> 'cancelled'::public.booking_status
    then
      return jsonb_build_object(
        'attending', true,
        'booking_id', v_booking.id,
        'status', v_booking.status
      );
    end if;

    select *
    into v_booking
    from public.book_class_slot(p_slot_id, null::smallint);

    return jsonb_build_object(
      'attending', true,
      'booking_id', v_booking.id,
      'status', v_booking.status
    );
  end if;

  if v_booking.id is not null
    and v_booking.status <> 'cancelled'::public.booking_status
  then
    select *
    into v_booking
    from public.cancel_my_booking(v_booking.id);
  end if;

  return jsonb_build_object(
    'attending', false,
    'booking_id', case when v_booking.id is null then null else v_booking.id end,
    'status', null
  );
end;
$function$
