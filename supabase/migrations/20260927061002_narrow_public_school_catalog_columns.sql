revoke select on public.dance_group from anon;
revoke select on public.group_trainers from anon;
revoke select on public.venues from anon;

grant select (
  id,
  style_id,
  title,
  description,
  level,
  max_capacity,
  enrollment_status,
  starts_on,
  ends_on,
  active
) on public.dance_group to anon;

grant select (
  group_id,
  trainer_id,
  trainer_role,
  starts_on,
  ends_on
) on public.group_trainers to anon;

grant select (
  id,
  name,
  address,
  latitude,
  longitude,
  capacity,
  active
) on public.venues to anon;
