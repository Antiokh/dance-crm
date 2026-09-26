-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   archive
-- Function: diff_text
-- Updated:  2026-09-26T20:33:08.279Z

-- overload
-- language: sql
-- args: old_text text, new_text text
-- returns: TABLE(line_no integer, old_line text, new_line text)

CREATE OR REPLACE FUNCTION archive.diff_text(old_text text, new_text text)
 RETURNS TABLE(line_no integer, old_line text, new_line text)
 LANGUAGE sql
AS $function$
    select
        row_number() over ()::integer as line_no,
        o.line,
        n.line
    from regexp_split_to_table(coalesce(old_text, ''), E'\n') with ordinality o(line, ord)
    full join regexp_split_to_table(coalesce(new_text, ''), E'\n') with ordinality n(line, ord)
        using (ord)
    where o.line is distinct from n.line;
$function$
