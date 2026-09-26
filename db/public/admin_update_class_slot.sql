-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_update_class_slot
-- Updated:  2026-09-26T20:35:31.905Z

-- overload
-- language: plpgsql
-- args: p_slot_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_venue_id uuid, p_capacity_override integer, p_visibility class_visibility, p_trainer_ids uuid[] DEFAULT NULL::uuid[]
-- returns: class_slots

CREATE OR REPLACE FUNCTION public.admin_update_class_slot(p_slot_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_venue_id uuid, p_capacity_override integer, p_visibility class_visibility, p_trainer_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS class_slots
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_slot public.class_slots;
  v_trainer_id uuid;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  update public.class_slots
  set starts_at = p_starts_at,
      ends_at = p_ends_at,
      venue_id = p_venue_id,
      capacity_override = p_capacity_override,
      visibility = p_visibility
  where id = p_slot_id
    and status = 'scheduled'::public.class_slot_status
  returning * into v_slot;

  if not found then
    raise exception 'scheduled class slot not found'
      using errcode='P0002';
  end if;

  if p_trainer_ids is not null then
    delete from public.class_slot_instructors
    where slot_id = p_slot_id;

    foreach v_trainer_id in array p_trainer_ids
    loop
      insert into public.class_slot_instructors (
        slot_id,
        trainer_id,
        trainer_role
      )
      values (
        p_slot_id,
        v_trainer_id,
        'lead'::public.group_trainer_role
      );
    end loop;
  end if;

  return v_slot;
end;
$function$
