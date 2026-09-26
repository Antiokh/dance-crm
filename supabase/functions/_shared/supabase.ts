import { createClient } from 'npm:@supabase/supabase-js@2';

import { requireEnv } from './env.ts';

function getSupabaseUrl(): string {
    return requireEnv('SUPABASE_URL');
}

function getAnonKey(): string {
    return requireEnv('SUPABASE_ANON_KEY');
}

function getServiceRoleKey(): string {
    return requireEnv('SUPABASE_SERVICE_ROLE_KEY');
}

export function supabaseAnon() {
    return createClient(getSupabaseUrl(), getAnonKey());
}

export function supabaseService() {
    return createClient(getSupabaseUrl(), getServiceRoleKey());
}

export function supabaseFromRequest(req: Request) {
    const authorization = req.headers.get('authorization');
    if (!authorization?.startsWith('Bearer ')) return null;

    return createClient(getSupabaseUrl(), getAnonKey(), {
        global: {
            headers: {
                Authorization: authorization,
            },
        },
    });
}
