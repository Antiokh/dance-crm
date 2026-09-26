import { createCors } from '../_shared/cors.ts';
import { supabaseFromRequest } from '../_shared/supabase.ts';

Deno.serve(async req => {
    const cors = createCors(req);

    if (cors.isOptions) return cors.preflight();
    if (cors.blocked) return cors.respond();

    const supabase = supabaseFromRequest(req);
    if (!supabase) {
        return cors.json({ error: 'Missing user bearer token' }, 401);
    }

    const {
        data: { user },
        error,
    } = await supabase.auth.getUser();

    if (error) {
        return cors.json({ error: error.message }, 401);
    }

    return cors.json({
        ok: true,
        user: user
            ? {
                  id: user.id,
                  email: user.email ?? null,
                  phone: user.phone ?? null,
                  role: user.role ?? null,
                  app_metadata: user.app_metadata ?? {},
                  user_metadata: user.user_metadata ?? {},
              }
            : null,
    });
});
