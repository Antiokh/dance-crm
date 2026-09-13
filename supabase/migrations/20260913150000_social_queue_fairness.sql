-- Guarantee that scheduled publications are not starved by a continuous transactional stream.
-- Per destination, allow at most four consecutive transactional claims while a scheduled job is ready.

alter table public.social_destinations
  add column if not exists transactional_streak integer not null default 0
  check (transactional_streak >= 0);

create or replace function public.social_claim_publication_jobs(
  p_worker_id text,
  p_transactional_limit integer default 8,
  p_scheduled_limit integer default 2,
  p_lease_seconds integer default 300
)
returns setof public.social_publication_jobs
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_lane text;
  v_lane_limit integer;
  v_claimed integer;
  v_job public.social_publication_jobs%rowtype;
  v_lease_seconds integer := least(greatest(coalesce(p_lease_seconds,300),60),3600);
begin
  if nullif(btrim(p_worker_id),'') is null then
    raise exception 'worker_id is required' using errcode = '22023';
  end if;

  update public.social_publication_jobs
  set status = 'cancelled',
      last_error = coalesce(last_error, 'job expired before delivery'),
      lease_owner = null,
      lease_expires_at = null
  where status in ('queued','retry','leased')
    and expires_at is not null
    and expires_at <= now()
    and (status <> 'leased' or lease_expires_at <= now());

  update public.social_publication_jobs
  set status = case when attempt_count >= max_attempts then 'dead' else 'retry' end,
      available_at = case when attempt_count >= max_attempts then available_at else now() + interval '60 seconds' end,
      last_error = coalesce(last_error, 'worker lease expired'),
      lease_owner = null,
      lease_expires_at = null
  where status = 'leased'
    and lease_expires_at <= now()
    and (expires_at is null or expires_at > now());

  foreach v_lane in array array['transactional','scheduled'] loop
    v_lane_limit := case
      when v_lane = 'transactional' then least(greatest(coalesce(p_transactional_limit,8),0),50)
      else least(greatest(coalesce(p_scheduled_limit,2),0),50)
    end;
    v_claimed := 0;

    while v_claimed < v_lane_limit loop
      select job.* into v_job
      from public.social_publication_jobs job
      join public.social_post_variants variant on variant.id = job.variant_id
      join public.social_posts post on post.id = variant.post_id
      join public.social_destinations destination on destination.key = job.destination_key
      where job.queue_class = v_lane
        and job.status in ('queued','retry')
        and job.attempt_count < job.max_attempts
        and job.scheduled_at <= now()
        and job.available_at <= now()
        and (job.expires_at is null or job.expires_at > now())
        and variant.status = 'approved'
        and post.status in ('approved','scheduled','partially_published')
        and destination.enabled
        and (destination.retry_after_at is null or destination.retry_after_at <= now())
        and (
          destination.last_claimed_at is null
          or destination.last_claimed_at <= now() - make_interval(secs => destination.min_publish_interval_seconds)
        )
        and not exists (
          select 1 from public.social_publication_jobs active
          where active.destination_key = job.destination_key
            and active.status = 'leased'
            and active.lease_expires_at > now()
        )
        and (
          job.depends_on_job_id is null
          or exists (
            select 1 from public.social_publication_jobs dependency
            where dependency.id = job.depends_on_job_id
              and dependency.status = 'published'
          )
        )
        and (
          v_lane <> 'transactional'
          or destination.transactional_streak < 4
          or not exists (
            select 1
            from public.social_publication_jobs waiting_scheduled
            join public.social_post_variants waiting_variant on waiting_variant.id = waiting_scheduled.variant_id
            join public.social_posts waiting_post on waiting_post.id = waiting_variant.post_id
            where waiting_scheduled.destination_key = job.destination_key
              and waiting_scheduled.queue_class = 'scheduled'
              and waiting_scheduled.status in ('queued','retry')
              and waiting_scheduled.attempt_count < waiting_scheduled.max_attempts
              and waiting_scheduled.scheduled_at <= now()
              and waiting_scheduled.available_at <= now()
              and (waiting_scheduled.expires_at is null or waiting_scheduled.expires_at > now())
              and waiting_variant.status = 'approved'
              and waiting_post.status in ('approved','scheduled','partially_published')
              and (
                waiting_scheduled.depends_on_job_id is null
                or exists (
                  select 1 from public.social_publication_jobs dep
                  where dep.id = waiting_scheduled.depends_on_job_id and dep.status = 'published'
                )
              )
          )
        )
      order by job.priority desc, job.available_at, job.scheduled_at, job.created_at
      for update of job skip locked
      limit 1;

      exit when not found;

      update public.social_publication_jobs
      set status = 'leased',
          attempt_count = attempt_count + 1,
          lease_owner = btrim(p_worker_id),
          lease_expires_at = now() + make_interval(secs => v_lease_seconds),
          last_error = null
      where id = v_job.id
      returning * into v_job;

      update public.social_destinations
      set last_claimed_at = now(),
          transactional_streak = case
            when v_lane = 'transactional' then transactional_streak + 1
            else 0
          end
      where key = v_job.destination_key;

      v_claimed := v_claimed + 1;
      return next v_job;
    end loop;
  end loop;
end;
$$;

revoke execute on function public.social_claim_publication_jobs(text,integer,integer,integer)
from public, anon, authenticated;
