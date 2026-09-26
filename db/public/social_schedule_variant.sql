-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: social_schedule_variant
-- Updated:  2026-09-26T20:35:14.784Z

-- overload
-- language: plpgsql
-- args: p_variant_id uuid, p_destination_key text, p_scheduled_at timestamp with time zone DEFAULT now(), p_queue_class text DEFAULT 'scheduled'::text, p_priority integer DEFAULT 0, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_depends_on_job_id uuid DEFAULT NULL::uuid, p_max_attempts integer DEFAULT 5, p_metadata jsonb DEFAULT '{}'::jsonb
-- returns: social_publication_jobs

CREATE OR REPLACE FUNCTION public.social_schedule_variant(p_variant_id uuid, p_destination_key text, p_scheduled_at timestamp with time zone DEFAULT now(), p_queue_class text DEFAULT 'scheduled'::text, p_priority integer DEFAULT 0, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_depends_on_job_id uuid DEFAULT NULL::uuid, p_max_attempts integer DEFAULT 5, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS social_publication_jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare v_variant public.social_post_variants; v_post public.social_posts; v_destination public.social_destinations; v_job public.social_publication_jobs; v_key text; v_limit integer;
begin
 if p_queue_class not in ('scheduled','transactional') then raise exception 'invalid queue_class' using errcode='22023'; end if;
 if p_priority < -1000 or p_priority > 1000 then raise exception 'priority must be between -1000 and 1000' using errcode='22023'; end if;
 if p_max_attempts < 1 or p_max_attempts > 20 then raise exception 'max_attempts must be between 1 and 20' using errcode='22023'; end if;
 if p_expires_at is not null and p_expires_at <= p_scheduled_at then raise exception 'expires_at must be after scheduled_at' using errcode='22023'; end if;
 select * into v_variant from public.social_post_variants where id=p_variant_id for update; if not found then raise exception 'social post variant not found' using errcode='P0002'; end if;
 if v_variant.status <> 'approved' then raise exception 'variant must be approved before scheduling' using errcode='55000'; end if;
 select * into v_post from public.social_posts where id=v_variant.post_id for update; if not found then raise exception 'parent social post not found' using errcode='P0002'; end if;
 if v_post.status not in ('approved','scheduled','partially_published') then raise exception 'post status % does not allow scheduling',v_post.status using errcode='55000'; end if;
 select * into v_destination from public.social_destinations where key=p_destination_key; if not found then raise exception 'social destination not found' using errcode='P0002'; end if;
 if not v_destination.enabled then raise exception 'social destination is disabled' using errcode='55000'; end if;
 if v_variant.platform <> v_destination.platform then raise exception 'variant platform % does not match destination platform %',v_variant.platform,v_destination.platform using errcode='22023'; end if;
 v_limit:=coalesce(v_variant.character_limit,v_destination.default_character_limit); if v_limit is not null and v_variant.character_count>v_limit then raise exception 'variant exceeds destination character limit' using errcode='22001'; end if;
 if p_depends_on_job_id is not null and not exists(select 1 from public.social_publication_jobs where id=p_depends_on_job_id) then raise exception 'dependency job not found' using errcode='P0002'; end if;
 v_key:=encode(digest(v_post.dedupe_key||':'||p_destination_key||':'||v_variant.variant_key||':'||p_queue_class,'sha256'),'hex');
 select * into v_job from public.social_publication_jobs where idempotency_key=v_key for update;
 if found and v_job.status='published' then return v_job;
 elsif found and v_job.status='leased' and v_job.lease_expires_at>now() then raise exception 'cannot reschedule an actively leased publication job' using errcode='55000';
 elsif found then update public.social_publication_jobs set variant_id=p_variant_id,destination_key=p_destination_key,queue_class=p_queue_class,priority=p_priority,status='queued',scheduled_at=p_scheduled_at,available_at=now(),expires_at=p_expires_at,depends_on_job_id=p_depends_on_job_id,attempt_count=0,max_attempts=p_max_attempts,lease_owner=null,lease_expires_at=null,published_at=null,external_post_id=null,external_post_url=null,last_error=null,provider_response='{}'::jsonb,metadata=coalesce(p_metadata,'{}'::jsonb) where id=v_job.id returning * into v_job;
 else insert into public.social_publication_jobs(variant_id,destination_key,idempotency_key,queue_class,priority,status,scheduled_at,available_at,expires_at,depends_on_job_id,max_attempts,metadata) values(p_variant_id,p_destination_key,v_key,p_queue_class,p_priority,'queued',p_scheduled_at,now(),p_expires_at,p_depends_on_job_id,p_max_attempts,coalesce(p_metadata,'{}'::jsonb)) returning * into v_job; end if;
 update public.social_posts set status=case when status='partially_published' then status else 'scheduled' end,target_publish_at=least(coalesce(target_publish_at,p_scheduled_at),p_scheduled_at) where id=v_post.id;
 return v_job;
end; $function$
