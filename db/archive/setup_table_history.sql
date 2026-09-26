-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: setup_table_history
-- Updated:  2026-09-26T21:42:01.606Z

-- overload
-- language: plpgsql
-- args: schema_name text DEFAULT 'public'::text
-- returns: void

CREATE OR REPLACE FUNCTION archive.setup_table_history(schema_name text DEFAULT 'public'::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  table_record record;
  v_ddl text;
BEGIN
  UPDATE archive.table_history th
  SET active = false
  WHERE th.schema_name = setup_table_history.schema_name;

  FOR table_record IN (
    SELECT
      n.nspname AS schema_name,
      c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = setup_table_history.schema_name
      AND c.relkind IN ('r', 'p')
  )
  LOOP
    v_ddl := archive.build_table_ddl(table_record.table_name, table_record.schema_name);

    PERFORM archive.save_table_history(
      table_record.table_name,
      v_ddl,
      table_record.schema_name
    );
  END LOOP;
END;
$function$
