-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   private
-- Function: effective_slot_capacity
-- Updated:  2026-09-26T20:33:31.931Z

-- overload
-- language: sql
-- args: p_slot_id uuid
-- returns: integer

CREATE OR REPLACE FUNCTION private.effective_slot_capacity(p_slot_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    when v.capacity is null then
      coalesce(cs.capacity_override, g.max_capacity)
    when coalesce(cs.capacity_override, g.max_capacity) is null then
      v.capacity
    else least(
      coalesce(cs.capacity_override, g.max_capacity),
      v.capacity
    )
  end
  from public.class_slots cs
  join public.dance_group g on g.id = cs.group_id
  left join public.venues v on v.id = cs.venue_id
  where cs.id = p_slot_id
$function$
