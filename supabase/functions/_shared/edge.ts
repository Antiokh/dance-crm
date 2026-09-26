import { requireEnv } from './env.ts';

function edgeBaseUrl(): string {
    const supabaseUrl = requireEnv('SUPABASE_URL').replace(/\/$/, '');
    return `${supabaseUrl}/functions/v1`;
}

export function edgeUrl(path: string): string {
    const normalizedPath = path.replace(/^\//, '');
    return `${edgeBaseUrl()}/${normalizedPath}`;
}

export async function edgeServiceFetch(path: string, init: RequestInit = {}) {
    const token = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
    const headers = new Headers(init.headers || {});
    headers.set('Authorization', `Bearer ${token}`);
    headers.set('apikey', token);

    return fetch(edgeUrl(path), { ...init, headers });
}

export async function edgeAnonFetch(path: string, init: RequestInit = {}) {
    const token = requireEnv('SUPABASE_ANON_KEY');
    const headers = new Headers(init.headers || {});
    headers.set('Authorization', `Bearer ${token}`);
    headers.set('apikey', token);

    return fetch(edgeUrl(path), { ...init, headers });
}

export async function edgeUserFetch(req: Request, path: string, init: RequestInit = {}) {
    const authorization = req.headers.get('authorization');
    if (!authorization?.startsWith('Bearer ')) {
        throw new Error('Missing user bearer token');
    }

    const headers = new Headers(init.headers || {});
    headers.set('Authorization', authorization);
    headers.set('apikey', requireEnv('SUPABASE_ANON_KEY'));

    return fetch(edgeUrl(path), { ...init, headers });
}

