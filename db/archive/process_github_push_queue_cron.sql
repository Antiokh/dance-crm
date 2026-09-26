-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: process_github_push_queue_cron
-- Updated:  2026-09-26T21:43:07.289Z

-- overload
-- language: plpgsql
-- args: p_limit integer DEFAULT 5
-- returns: integer

CREATE OR REPLACE FUNCTION archive.process_github_push_queue_cron(p_limit integer DEFAULT 5)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
begin
  return archive.process_github_push_queue(p_limit);
end;
$function$
