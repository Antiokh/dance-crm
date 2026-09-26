-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: update_tables
-- Updated:  2026-09-26T22:01:35.271Z

-- overload
-- language: plpgsql
-- args: p_schema_name text DEFAULT 'public'::text
-- returns: TABLE(table_history_id bigint, schema_name text, table_name text)

CREATE OR REPLACE FUNCTION archive.update_tables(p_schema_name text DEFAULT 'public'::text)
 RETURNS TABLE(table_history_id bigint, schema_name text, table_name text)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
declare
    v_table record;
    v_changed boolean;
    v_last_id bigint;
    v_ddl text;
    v_previous_tables text[];
    v_dropped_table text;
    v_next_version integer;
begin
    select coalesce(array_agg(th.table_name order by th.table_name), array[]::text[])
    into v_previous_tables
    from archive.table_history th
    where th.schema_name = p_schema_name
      and th.active = true
      and not th.dropped;

    update archive.table_history th
    set active = false
    where th.schema_name = p_schema_name;

    for v_table in
        select
            n.nspname as schema_name,
            c.relname as table_name
        from pg_catalog.pg_class c
        join pg_catalog.pg_namespace n on n.oid = c.relnamespace
        where n.nspname = p_schema_name
          and c.relkind in ('r', 'p')
        order by c.relname
    loop
        v_ddl := archive.build_table_ddl(v_table.table_name, v_table.schema_name);

        v_changed := archive.update_table_history(
            v_table.table_name,
            v_ddl,
            v_table.schema_name
        );

        if v_changed then
            select th.id
            into v_last_id
            from archive.table_history th
            where th.schema_name = v_table.schema_name
              and th.table_name = v_table.table_name
            order by th.id desc
            limit 1;

            table_history_id := v_last_id;
            schema_name := v_table.schema_name;
            table_name := v_table.table_name;
            return next;
        end if;
    end loop;

    foreach v_dropped_table in array v_previous_tables
    loop
        if not exists (
            select 1
            from pg_catalog.pg_class c
            join pg_catalog.pg_namespace n on n.oid = c.relnamespace
            where n.nspname = p_schema_name
              and c.relname = v_dropped_table
              and c.relkind in ('r', 'p')
        ) then
            select coalesce(max(th.version), 0) + 1
            into v_next_version
            from archive.table_history th
            where th.schema_name = p_schema_name
              and th.table_name = v_dropped_table;

            insert into archive.table_history (
                schema_name,
                table_name,
                ddl,
                version,
                active,
                dropped
            )
            values (
                p_schema_name,
                v_dropped_table,
                format('DROP TABLE %I.%I;', p_schema_name, v_dropped_table),
                v_next_version,
                false,
                true
            )
            returning id into v_last_id;

            table_history_id := v_last_id;
            schema_name := p_schema_name;
            table_name := v_dropped_table;
            return next;
        end if;
    end loop;
end;
$function$
