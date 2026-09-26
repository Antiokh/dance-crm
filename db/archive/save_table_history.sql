-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: save_table_history
-- Updated:  2026-09-26T22:01:31.380Z

-- overload
-- language: plpgsql
-- args: p_table_name text, p_ddl text, p_schema_name text DEFAULT 'public'::text
-- returns: void

CREATE OR REPLACE FUNCTION archive.save_table_history(p_table_name text, p_ddl text, p_schema_name text DEFAULT 'public'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'archive', 'public', 'extensions'
AS $function$
declare
    v_prev_id bigint;
    v_prev_ddl text;
    v_prev_dropped boolean;
    v_next_version integer;
begin
    select th.id, th.ddl, th.dropped
    into v_prev_id, v_prev_ddl, v_prev_dropped
    from archive.table_history th
    where th.schema_name = p_schema_name
      and th.table_name = p_table_name
    order by th.id desc
    limit 1;

    if v_prev_ddl is not null
       and not coalesce(v_prev_dropped, false)
       and not exists (select 1 from archive.diff_text(v_prev_ddl, p_ddl))
    then
        update archive.table_history th
        set active = false
        where th.schema_name = p_schema_name
          and th.table_name = p_table_name;

        update archive.table_history
        set active = true
        where id = v_prev_id;

        return;
    end if;

    select coalesce(max(th.version), 0) + 1
    into v_next_version
    from archive.table_history th
    where th.schema_name = p_schema_name
      and th.table_name = p_table_name;

    update archive.table_history th
    set active = false
    where th.schema_name = p_schema_name
      and th.table_name = p_table_name;

    insert into archive.table_history (
        schema_name, table_name, ddl, version, active, dropped
    )
    values (
        p_schema_name, p_table_name, p_ddl, v_next_version, true, false
    );
end;
$function$
