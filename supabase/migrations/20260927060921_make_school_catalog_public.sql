grant select on public.dance_group to anon;
grant select on public.group_trainers to anon;
grant select on public.venues to anon;

grant select (
  id,
  custom_name,
  first_name,
  last_name,
  telegram_username
) on public.dancer to anon;

drop policy if exists dance_group_public_select on public.dance_group;
create policy dance_group_public_select
on public.dance_group
for select
to anon
using (active);

drop policy if exists group_trainers_public_select on public.group_trainers;
create policy group_trainers_public_select
on public.group_trainers
for select
to anon
using (
  exists (
    select 1
    from public.dance_group g
    where g.id = group_trainers.group_id
      and g.active
  )
);

drop policy if exists venues_public_select on public.venues;
create policy venues_public_select
on public.venues
for select
to anon
using (active);

drop policy if exists dancer_public_trainers_select on public.dancer;
create policy dancer_public_trainers_select
on public.dancer
for select
to anon
using (
  exists (
    select 1
    from public.group_trainers gt
    join public.dance_group g on g.id = gt.group_id
    where gt.trainer_id = dancer.id
      and g.active
      and (gt.starts_on is null or gt.starts_on <= current_date)
      and (gt.ends_on is null or gt.ends_on >= current_date)
  )
);
