-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase database function versioning
-- Schema:   public
-- Function: update_user_password
-- Updated:  2026-09-26T20:34:43.316Z

-- overload
-- language: plpgsql
-- args: p_user_id uuid, p_new_password text
-- returns: void

CREATE OR REPLACE FUNCTION public.update_user_password(p_user_id uuid, p_new_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update auth.users
  set encrypted_password = extensions.crypt(
        p_new_password,
        extensions.gen_salt('bf')
      ),
      updated_at = now()
  where id = p_user_id;

  if not found then
    raise exception 'auth user not found' using errcode='P0002';
  end if;
end;
$function$
