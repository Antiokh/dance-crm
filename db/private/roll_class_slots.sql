-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: roll_class_slots
-- Updated:  2026-09-27T00:31:02.715Z

-- overload
-- language: plpgsql
-- args: 
-- returns: jsonb

CREATE OR REPLACE FUNCTION private.roll_class_slots()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_schedule record;
  v_completed integer := 0;
  v_created integer := 0;
begin
  update public.class_slots
  set status = 'completed'::public.class_slot_status
  where status = 'scheduled'::public.class_slot_status
    and ends_at <= now();

  get diagnostics v_completed = row_count;

  for v_schedule in
    select id
    from public.class_schedules
    where active
      and valid_from <= current_date
      and (
        valid_until is null
        or valid_until >= current_date
      )
    order by id
  loop
    if private.ensure_next_class_slot(v_schedule.id) then
      v_created := v_created + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'completed', v_completed,
    'created', v_created
  );
end;
$function$
