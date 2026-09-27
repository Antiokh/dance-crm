-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: admin_save_group
-- Updated:  2026-09-27T09:51:00.707Z

-- overload
-- language: plpgsql
-- args: p_group_id uuid, p_payload jsonb
-- returns: uuid

CREATE OR REPLACE FUNCTION public.admin_save_group(p_group_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_group_id uuid := p_group_id;
  v_lead_trainer_id uuid;
begin
  if not private.has_app_role('administrator'::public.app_role) then
    raise exception 'administrator role required' using errcode='42501';
  end if;

  begin
    v_lead_trainer_id :=
      nullif(btrim(p_payload->>'lead_trainer_id'),'')::uuid;
  exception when others then
    raise exception 'invalid lead trainer id' using errcode='22023';
  end;

  if v_group_id is null then
    v_group_id := extensions.gen_random_uuid();

    insert into public.dance_group(
      id,
      style_id,
      description,
      level_id,
      max_capacity,
      approval_required,
      enrollment_status,
      starts_on,
      ends_on,
      active
    )
    values(
      v_group_id,
      (p_payload->>'style_id')::smallint,
      nullif(btrim(p_payload->>'description'),''),
      nullif(p_payload->>'level_id','')::bigint,
      nullif(p_payload->>'max_capacity','')::integer,
      coalesce((p_payload->>'approval_required')::boolean,false),
      coalesce(
        nullif(btrim(p_payload->>'enrollment_status'),''),
        'open'
      )::public.group_enrollment_status,
      nullif(p_payload->>'starts_on','')::date,
      nullif(p_payload->>'ends_on','')::date,
      coalesce((p_payload->>'active')::boolean,true)
    );
  else
    update public.dance_group
    set style_id=(p_payload->>'style_id')::smallint,
        description=nullif(btrim(p_payload->>'description'),''),
        level_id=nullif(p_payload->>'level_id','')::bigint,
        max_capacity=nullif(p_payload->>'max_capacity','')::integer,
        approval_required=coalesce(
          (p_payload->>'approval_required')::boolean,
          approval_required
        ),
        enrollment_status=coalesce(
          nullif(btrim(p_payload->>'enrollment_status'),''),
          enrollment_status::text
        )::public.group_enrollment_status,
        starts_on=nullif(p_payload->>'starts_on','')::date,
        ends_on=nullif(p_payload->>'ends_on','')::date,
        active=coalesce((p_payload->>'active')::boolean,active)
    where id=v_group_id;

    if not found then
      raise exception 'dance group not found' using errcode='P0002';
    end if;
  end if;

  delete from public.group_trainers
  where group_id=v_group_id
    and trainer_role='lead'::public.group_trainer_role;

  if v_lead_trainer_id is not null then
    insert into public.group_trainers(
      group_id,
      trainer_id,
      trainer_role,
      starts_on,
      ends_on
    )
    values(
      v_group_id,
      v_lead_trainer_id,
      'lead'::public.group_trainer_role,
      nullif(p_payload->>'starts_on','')::date,
      nullif(p_payload->>'ends_on','')::date
    );
  end if;

  return v_group_id;
end;
$function$
