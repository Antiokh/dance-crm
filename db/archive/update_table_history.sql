-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: update_table_history
-- Updated:  2026-09-26T21:42:04.133Z

-- overload
-- language: plpgsql
-- args: p_table_name text, p_ddl text, p_schema_name text DEFAULT 'public'::text
-- returns: boolean

CREATE OR REPLACE FUNCTION archive.update_table_history(p_table_name text, p_ddl text, p_schema_name text DEFAULT 'public'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'archive'
AS $function$
declare
    v_prev_id bigint;
    v_prev_ddl text;
    v_prev_active boolean;
    v_prev_dropped boolean;
    v_next_version integer;
begin
    select th.id, th.ddl, th.active, th.dropped
    into v_prev_id, v_prev_ddl, v_prev_active, v_prev_dropped
    from archive.table_history th
    where th.schema_name = p_schema_name
      and th.table_name = p_table_name
    order by th.id desc
    limit 1;

    if v_prev_ddl is not null
       and not coalesce(v_prev_dropped, false)
       and not exists (select 1 from archive.diff_text(v_prev_ddl, p_ddl))
    then
        if not coalesce(v_prev_active, false) then
            update archive.table_history th
            set active = false
            where th.schema_name = p_schema_name
              and th.table_name = p_table_name;

            update archive.table_history
            set active = true
            where id = v_prev_id;
        end if;

        return false;
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

    return true;
end;
$function$
