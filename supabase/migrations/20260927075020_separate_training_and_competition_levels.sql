
alter table public.styles_levels
  add column kind text not null default 'training',
  add column system_code text not null default 'school',
  add column is_sport_achievement boolean not null default false,
  add column description text;

alter table public.styles_levels
  add constraint styles_levels_kind_check
  check (kind in ('training', 'competition'));

alter table public.styles_levels
  add constraint styles_levels_system_code_check
  check (length(btrim(system_code)) between 1 and 64);

alter table public.styles_levels
  drop constraint styles_levels_style_id_code_key;

alter table public.styles_levels
  add constraint styles_levels_style_system_code_key
  unique (style_id, system_code, code);

update public.styles_levels l
set kind='competition',
    system_code='wsdc',
    is_sport_achievement=false,
    description='WSDC base competition class; trophy status starts after advancing beyond the entry class.'
from public.l_dance_style s
where s.id=l.style_id
  and s.title_en='West-Coast Swing'
  and l.code='novice';

update public.styles_levels l
set kind='training',
    system_code='school',
    is_sport_achievement=false,
    title_en='Beginner',
    title_ru='Beginner',
    description='School training level.'
from public.l_dance_style s
where s.id=l.style_id
  and s.title_en='West-Coast Swing'
  and l.code='beginner';

insert into public.styles_levels(
  style_id,system_code,kind,code,title_en,title_ru,rank_order,is_sport_achievement,description
)
select s.id,'school','training',x.code,x.title_en,x.title_ru,x.rank_order,false,'School training level.'
from public.l_dance_style s
cross join (values
  ('beginner', 'Beginner', 'Beginner', 10::smallint),
  ('beginner_plus', 'Beginner+', 'Beginner+', 20::smallint),
  ('intermediate', 'Intermediate', 'Intermediate', 30::smallint),
  ('intermediate_plus', 'Intermediate+', 'Intermediate+', 40::smallint),
  ('advanced', 'Advanced', 'Advanced', 50::smallint)
) as x(code,title_en,title_ru,rank_order)
where s.title_en in ('West-Coast Swing','Hustle')
on conflict (style_id,system_code,code) do update
set kind=excluded.kind,
    title_en=excluded.title_en,
    title_ru=excluded.title_ru,
    rank_order=excluded.rank_order,
    is_sport_achievement=excluded.is_sport_achievement,
    description=excluded.description,
    active=true;

insert into public.styles_levels(
  style_id,system_code,kind,code,title_en,title_ru,rank_order,is_sport_achievement,description
)
select s.id,'wsdc','competition',x.code,x.title_en,x.title_ru,x.rank_order,x.sport,x.description
from public.l_dance_style s
cross join (values
  ('newcomer','Newcomer','Newcomer',100::smallint,false,'Optional WSDC entry division; not treated as an earned sport class in the app.'),
  ('novice','Novice','Novice',110::smallint,false,'WSDC entry/base class; trophy status starts after advancement to Intermediate.'),
  ('intermediate','Intermediate','Intermediate',120::smallint,true,'Earned WSDC competition class.'),
  ('advanced','Advanced','Advanced',130::smallint,true,'Earned WSDC competition class.'),
  ('all_star','All Star','All Star',140::smallint,true,'Earned WSDC competition class.'),
  ('champion','Champion','Champion',150::smallint,true,'Earned WSDC competition class.')
) as x(code,title_en,title_ru,rank_order,sport,description)
where s.title_en='West-Coast Swing'
on conflict (style_id,system_code,code) do update
set kind=excluded.kind,
    title_en=excluded.title_en,
    title_ru=excluded.title_ru,
    rank_order=excluded.rank_order,
    is_sport_achievement=excluded.is_sport_achievement,
    description=excluded.description,
    active=true;

insert into public.styles_levels(
  style_id,system_code,kind,code,title_en,title_ru,rank_order,is_sport_achievement,description
)
select s.id,'ash_pair','competition',x.code,x.title_en,x.title_ru,x.rank_order,x.sport,x.description
from public.l_dance_style s
cross join (values
  ('e','E','E',100::smallint,false,'ASH debut pair class; not treated as an earned sport class in the app.'),
  ('d','D','D',110::smallint,true,'Earned ASH pair class.'),
  ('c','C','C',120::smallint,true,'Earned ASH pair class.'),
  ('b','B','B',130::smallint,true,'Earned ASH pair class.'),
  ('a','A','A',140::smallint,true,'Earned ASH pair class.')
) as x(code,title_en,title_ru,rank_order,sport,description)
where s.title_en='Hustle'
on conflict (style_id,system_code,code) do update
set kind=excluded.kind,
    title_en=excluded.title_en,
    title_ru=excluded.title_ru,
    rank_order=excluded.rank_order,
    is_sport_achievement=excluded.is_sport_achievement,
    description=excluded.description,
    active=true;

insert into public.styles_levels(
  style_id,system_code,kind,code,title_en,title_ru,rank_order,is_sport_achievement,description
)
select s.id,'ash_jnj','competition',x.code,x.title_en,x.title_ru,x.rank_order,x.sport,x.description
from public.l_dance_style s
cross join (values
  ('beginner','Beginner','Beginner',200::smallint,false,'ASH JnJ debut class; not treated as an earned sport class in the app.'),
  ('rising_star','Rising Star','Rising Star',210::smallint,true,'Earned ASH JnJ class.'),
  ('main','Main','Main',220::smallint,true,'Earned ASH JnJ class.'),
  ('star','Star','Star',230::smallint,true,'Earned ASH JnJ class.'),
  ('champion','Champion','Champion',240::smallint,true,'Earned ASH JnJ class.')
) as x(code,title_en,title_ru,rank_order,sport,description)
where s.title_en='Hustle'
on conflict (style_id,system_code,code) do update
set kind=excluded.kind,
    title_en=excluded.title_en,
    title_ru=excluded.title_ru,
    rank_order=excluded.rank_order,
    is_sport_achievement=excluded.is_sport_achievement,
    description=excluded.description,
    active=true;

create table public.dancer_style_competition_profile (
  id uuid primary key default extensions.gen_random_uuid(),
  style_profile_id uuid not null references public.dancer_style_profile(id) on delete cascade,
  system_code text not null,
  level_id bigint not null references public.styles_levels(id) on delete restrict,
  points numeric(12,2),
  external_profile_id text,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(style_profile_id, system_code)
);

create trigger dancer_style_competition_profile_touch_updated_at
before update on public.dancer_style_competition_profile
for each row execute function private.touch_updated_at();

alter table public.dancer_style_competition_profile enable row level security;
grant select on public.dancer_style_competition_profile to authenticated;

create policy dancer_style_competition_profile_select_own
on public.dancer_style_competition_profile
for select
to authenticated
using (
  exists (
    select 1
    from public.dancer_style_profile p
    where p.id=style_profile_id
      and p.dancer_id=private.current_dancer_id()
  )
);

insert into public.dancer_style_competition_profile(
  style_profile_id,system_code,level_id,points
)
select p.id,l.system_code,p.level_id,0
from public.dancer_style_profile p
join public.styles_levels l on l.id=p.level_id and l.style_id=p.style_id
where p.level_id is not null
  and l.kind='competition'
on conflict(style_profile_id,system_code) do nothing;

alter table public.dancer_style_profile
  rename column level_id to training_level_id;

update public.dancer_style_profile p
set training_level_id=null
where exists (
  select 1
  from public.styles_levels l
  where l.id=p.training_level_id
    and l.style_id=p.style_id
    and l.kind='competition'
);

create or replace function private.validate_dancer_style_training_level()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if new.training_level_id is null then return new; end if;

  if not exists (
    select 1
    from public.styles_levels l
    where l.id=new.training_level_id
      and l.style_id=new.style_id
      and l.kind='training'
  ) then
    raise exception 'training level must belong to the same style and be kind=training'
      using errcode='23514';
  end if;

  return new;
end;
$function$;

revoke all on function private.validate_dancer_style_training_level()
from public,anon,authenticated;

create trigger dancer_style_profile_validate_training_level
before insert or update of training_level_id,style_id
on public.dancer_style_profile
for each row execute function private.validate_dancer_style_training_level();

create or replace function private.validate_dancer_style_competition_profile()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_style_id smallint;
begin
  select p.style_id into v_style_id
  from public.dancer_style_profile p
  where p.id=new.style_profile_id;

  if v_style_id is null then
    raise exception 'style profile not found' using errcode='23503';
  end if;

  if not exists (
    select 1
    from public.styles_levels l
    where l.id=new.level_id
      and l.style_id=v_style_id
      and l.kind='competition'
      and l.system_code=new.system_code
  ) then
    raise exception 'competition level must match style and system'
      using errcode='23514';
  end if;

  return new;
end;
$function$;

revoke all on function private.validate_dancer_style_competition_profile()
from public,anon,authenticated;

create trigger dancer_style_competition_profile_validate
before insert or update of style_profile_id,system_code,level_id
on public.dancer_style_competition_profile
for each row execute function private.validate_dancer_style_competition_profile();
