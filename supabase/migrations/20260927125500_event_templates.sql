-- Reusable templates for irregular dance events and an explicit admin access probe
-- used by authenticated Edge Functions.

create table if not exists public.event_templates (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  event_type public.dance_event_type not null,
  title text not null check (length(btrim(title)) > 0),
  description text,
  duration_minutes integer,
  venue_id uuid references public.venues(id) on delete set null,
  style_id smallint references public.l_dance_style(id) on delete set null,
  active boolean not null default true,
  created_by uuid references public.dancer(id) on delete set null
    default private.current_dancer_id(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_templates_duration_check
    check (duration_minutes is null or duration_minutes between 1 and 1440)
);

create index if not exists event_templates_active_name_idx
  on public.event_templates (active desc, name);

drop trigger if exists event_templates_touch_updated_at
  on public.event_templates;

create trigger event_templates_touch_updated_at
before update on public.event_templates
for each row execute function private.touch_updated_at();

alter table public.event_templates enable row level security;

grant select, insert, update, delete
  on public.event_templates to authenticated;

drop policy if exists event_templates_admin_select
  on public.event_templates;
create policy event_templates_admin_select
on public.event_templates
for select
to authenticated
using (private.has_app_role('administrator'::public.app_role));

drop policy if exists event_templates_admin_insert
  on public.event_templates;
create policy event_templates_admin_insert
on public.event_templates
for insert
to authenticated
with check (private.has_app_role('administrator'::public.app_role));

drop policy if exists event_templates_admin_update
  on public.event_templates;
create policy event_templates_admin_update
on public.event_templates
for update
to authenticated
using (private.has_app_role('administrator'::public.app_role))
with check (private.has_app_role('administrator'::public.app_role));

drop policy if exists event_templates_admin_delete
  on public.event_templates;
create policy event_templates_admin_delete
on public.event_templates
for delete
to authenticated
using (private.has_app_role('administrator'::public.app_role));

create or replace function public.is_current_administrator()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.has_app_role('administrator'::public.app_role)
$function$;

revoke all on function public.is_current_administrator()
  from public, anon;
grant execute on function public.is_current_administrator()
  to authenticated;
