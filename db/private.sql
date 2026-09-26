-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase table DDL versioning
-- Schema:   private
-- Entity:   tables
-- Mode:     table_bundle
-- Updated:  2026-09-26T21:37:03.017Z

-- table: dancer_style_orphans

CREATE TABLE private.dancer_style_orphans (
  source_table text NOT NULL,
  original_id uuid NOT NULL,
  row_data jsonb NOT NULL,
  quarantined_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT dancer_style_orphans_pkey PRIMARY KEY (source_table, original_id)
);
