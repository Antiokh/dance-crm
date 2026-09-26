-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_create_manual_class_slot
-- Updated:  2026-09-26T20:35:30.573Z

-- overload
-- language: plpgsql
-- args: p_group_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_venue_id uuid DEFAULT NULL::uuid, p_capacity_override integer DEFAULT NULL::integer, p_visibility class_visibility DEFAULT 'public'::class_visibility, p_trainer_ids uuid[] DEFAULT '{}'::uuid[]
-- returns: uuid

CREATE OR REPLACE FUNCTION public.admin_create_manual_class_slot(p_group_id uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_venue_id uuid DEFAULT NULL::uuid, p_capacity_override integer DEFAULT NULL::integer, p_visibility class_visibility DEFAULT 'public'::class_visibility, p_trainer_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_slot_id uuid;
  v_trainer_id uuid;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required'
      using errcode='42501';
  end if;

  insert into public.class_slots (
    group_id,
    starts_at,
    ends_at,
    venue_id,
    capacity_override,
    visibility,
    status,
    source
  )
  values (
    p_group_id,
    p_starts_at,
    p_ends_at,
    p_venue_id,
    p_capacity_override,
    p_visibility,
    'scheduled'::public.class_slot_status,
    'manual'::public.class_slot_source
  )
  returning id into v_slot_id;

  foreach v_trainer_id in array coalesce(p_trainer_ids, '{}'::uuid[])
  loop
    insert into public.class_slot_instructors (
      slot_id,
      trainer_id,
      trainer_role
    )
    values (
      v_slot_id,
      v_trainer_id,
      'lead'::public.group_trainer_role
    )
    on conflict do nothing;
  end loop;

  return v_slot_id;
end;
$function$
