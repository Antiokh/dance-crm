-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: social_mark_publication_succeeded
-- Updated:  2026-09-26T20:35:16.116Z

-- overload
-- language: plpgsql
-- args: p_job_id uuid, p_worker_id text, p_external_post_id text DEFAULT NULL::text, p_external_post_url text DEFAULT NULL::text, p_provider_response jsonb DEFAULT '{}'::jsonb
-- returns: social_publication_jobs

CREATE OR REPLACE FUNCTION public.social_mark_publication_succeeded(p_job_id uuid, p_worker_id text, p_external_post_id text DEFAULT NULL::text, p_external_post_url text DEFAULT NULL::text, p_provider_response jsonb DEFAULT '{}'::jsonb)
 RETURNS social_publication_jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$ declare v_job public.social_publication_jobs; v_post_id uuid; begin
 update public.social_publication_jobs set status='published',published_at=now(),external_post_id=p_external_post_id,external_post_url=p_external_post_url,provider_response=coalesce(p_provider_response,'{}'::jsonb),last_error=null,lease_owner=null,lease_expires_at=null where id=p_job_id and status='leased' and lease_owner=p_worker_id returning * into v_job; if not found then raise exception 'leased publication job not found for this worker' using errcode='P0002'; end if;
 select post_id into v_post_id from public.social_post_variants where id=v_job.variant_id;
 update public.social_posts set status=case when exists(select 1 from public.social_publication_jobs j join public.social_post_variants v on v.id=j.variant_id where v.post_id=v_post_id and j.status not in ('published','cancelled')) then 'partially_published' else 'published' end where id=v_post_id and status not in ('stale','cancelled'); return v_job; end; $function$
