-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: get_complete_schema
-- Updated:  2026-09-26T22:01:45.570Z

-- overload
-- language: sql
-- args: 
-- returns: jsonb

CREATE OR REPLACE FUNCTION public.get_complete_schema()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'captured_at', now(),
    'schemas', (
      select coalesce(jsonb_agg(schema_payload order by schema_name), '[]'::jsonb)
      from (
        select
          ns.nspname as schema_name,
          jsonb_build_object(
            'name', ns.nspname,
            'enums', (
              select coalesce(jsonb_agg(
                jsonb_build_object(
                  'name', t.typname,
                  'values', (
                    select jsonb_agg(e.enumlabel order by e.enumsortorder)
                    from pg_catalog.pg_enum e
                    where e.enumtypid = t.oid
                  )
                ) order by t.typname
              ), '[]'::jsonb)
              from pg_catalog.pg_type t
              where t.typnamespace = ns.oid
                and t.typtype = 'e'
            ),
            'tables', (
              select coalesce(jsonb_agg(
                jsonb_build_object(
                  'name', c.relname,
                  'rls_enabled', c.relrowsecurity,
                  'columns', (
                    select coalesce(jsonb_agg(
                      jsonb_build_object(
                        'name', a.attname,
                        'type', pg_catalog.format_type(a.atttypid, a.atttypmod),
                        'not_null', a.attnotnull,
                        'default', pg_catalog.pg_get_expr(d.adbin, d.adrelid),
                        'identity', nullif(a.attidentity, '')
                      ) order by a.attnum
                    ), '[]'::jsonb)
                    from pg_catalog.pg_attribute a
                    left join pg_catalog.pg_attrdef d
                      on d.adrelid = a.attrelid
                     and d.adnum = a.attnum
                    where a.attrelid = c.oid
                      and a.attnum > 0
                      and not a.attisdropped
                  ),
                  'constraints', (
                    select coalesce(jsonb_agg(
                      jsonb_build_object(
                        'name', con.conname,
                        'type', con.contype,
                        'definition', pg_catalog.pg_get_constraintdef(con.oid, true)
                      ) order by con.conname
                    ), '[]'::jsonb)
                    from pg_catalog.pg_constraint con
                    where con.conrelid = c.oid
                  ),
                  'indexes', (
                    select coalesce(jsonb_agg(
                      jsonb_build_object(
                        'name', i.relname,
                        'definition', pg_catalog.pg_get_indexdef(i.oid)
                      ) order by i.relname
                    ), '[]'::jsonb)
                    from pg_catalog.pg_index ix
                    join pg_catalog.pg_class i on i.oid = ix.indexrelid
                    where ix.indrelid = c.oid
                  ),
                  'policies', (
                    select coalesce(jsonb_agg(
                      jsonb_build_object(
                        'name', pol.polname,
                        'command', pol.polcmd,
                        'roles', pol.polroles,
                        'using', pg_catalog.pg_get_expr(pol.polqual, pol.polrelid),
                        'check', pg_catalog.pg_get_expr(pol.polwithcheck, pol.polrelid)
                      ) order by pol.polname
                    ), '[]'::jsonb)
                    from pg_catalog.pg_policy pol
                    where pol.polrelid = c.oid
                  ),
                  'triggers', (
                    select coalesce(jsonb_agg(
                      jsonb_build_object(
                        'name', trg.tgname,
                        'definition', pg_catalog.pg_get_triggerdef(trg.oid, true)
                      ) order by trg.tgname
                    ), '[]'::jsonb)
                    from pg_catalog.pg_trigger trg
                    where trg.tgrelid = c.oid
                      and not trg.tgisinternal
                  )
                ) order by c.relname
              ), '[]'::jsonb)
              from pg_catalog.pg_class c
              where c.relnamespace = ns.oid
                and c.relkind in ('r', 'p')
            ),
            'views', (
              select coalesce(jsonb_agg(
                jsonb_build_object(
                  'name', c.relname,
                  'kind', case c.relkind when 'v' then 'view' else 'materialized_view' end,
                  'definition', pg_catalog.pg_get_viewdef(c.oid, true)
                ) order by c.relname
              ), '[]'::jsonb)
              from pg_catalog.pg_class c
              where c.relnamespace = ns.oid
                and c.relkind in ('v', 'm')
            ),
            'functions', (
              select coalesce(jsonb_agg(
                jsonb_build_object(
                  'name', p.proname,
                  'args', pg_catalog.pg_get_function_identity_arguments(p.oid),
                  'returns', pg_catalog.pg_get_function_result(p.oid),
                  'definition', archive.redact_function_source(pg_catalog.pg_get_functiondef(p.oid))
                ) order by p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid)
              ), '[]'::jsonb)
              from pg_catalog.pg_proc p
              where p.pronamespace = ns.oid
                and p.prokind = 'f'
            )
          ) as schema_payload
        from pg_catalog.pg_namespace ns
        where ns.nspname in ('archive', 'private', 'public')
      ) s
    )
  );
$function$
