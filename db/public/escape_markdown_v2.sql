-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: escape_markdown_v2
-- Updated:  2026-09-26T20:35:42.061Z

-- overload
-- language: plpgsql
-- args: input text
-- returns: text

CREATE OR REPLACE FUNCTION public.escape_markdown_v2(input text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare
  result text := input;
begin
  -- Все символы, требующие экранирования в MarkdownV2
  result := regexp_replace(result, '([_*\[\]()~`>\#\+\-=\|\{\}\.!])', '\\\1', 'g');
  return result;
end;
$function$
