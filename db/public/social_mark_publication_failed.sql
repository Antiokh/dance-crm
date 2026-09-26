-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: social_mark_publication_failed
-- Updated:  2026-09-26T20:35:17.421Z

-- overload
-- language: plpgsql
-- args: p_job_id uuid, p_worker_id text, p_error text, p_retry_after_seconds integer DEFAULT 300, p_terminal boolean DEFAULT false, p_provider_response jsonb DEFAULT '{}'::jsonb
-- returns: social_publication_jobs

CREATE OR REPLACE FUNCTION public.social_mark_publication_failed(p_job_id uuid, p_worker_id text, p_error text, p_retry_after_seconds integer DEFAULT 300, p_terminal boolean DEFAULT false, p_provider_response jsonb DEFAULT '{}'::jsonb)
 RETURNS social_publication_jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$ declare v_job public.social_publication_jobs; v_retry integer:=least(greatest(coalesce(p_retry_after_seconds,300),60),86400); begin
 update public.social_publication_jobs set status=case when p_terminal or attempt_count>=max_attempts then 'dead' else 'retry' end,available_at=case when p_terminal or attempt_count>=max_attempts then available_at else now()+make_interval(secs=>v_retry) end,last_error=coalesce(nullif(btrim(p_error),''),'unknown publication error'),provider_response=coalesce(p_provider_response,'{}'::jsonb),lease_owner=null,lease_expires_at=null where id=p_job_id and status='leased' and lease_owner=p_worker_id returning * into v_job; if not found then raise exception 'leased publication job not found for this worker' using errcode='P0002'; end if; return v_job; end; $function$
