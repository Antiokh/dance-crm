-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: create_user_telegram_metadata
-- Updated:  2026-09-26T20:34:41.885Z

-- overload
-- language: plpgsql
-- args: telegram_id bigint, password text, user_meta_data jsonb
-- returns: uuid

CREATE OR REPLACE FUNCTION public.create_user_telegram_metadata(telegram_id bigint, password text, user_meta_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  user_id uuid;
  encrypted_pw text;
  technical_email text;
begin
  user_id := extensions.gen_random_uuid();
  encrypted_pw := extensions.crypt(password, extensions.gen_salt('bf'));
  technical_email := telegram_id::text || '@t.me';

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, recovery_sent_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    user_id,
    'authenticated',
    'authenticated',
    technical_email,
    encrypted_pw,
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    user_meta_data,
    now(), now(),
    '', '', '', ''
  );

  insert into auth.identities (
    id, provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  )
  values (
    extensions.gen_random_uuid(),
    extensions.gen_random_uuid()::text,
    user_id,
    jsonb_build_object(
      'sub', user_id::text,
      'email', technical_email,
      'name', coalesce(user_meta_data->>'full_name', user_meta_data->>'username', '')
    ),
    'email',
    now(), now(), now()
  );

  return user_id;
end;
$function$
