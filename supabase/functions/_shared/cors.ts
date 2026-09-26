type CorsOptions = {
    allowedOrigins?: string[];
    allowCredentials?: boolean;
};

function buildHeaders(req: Request, options: CorsOptions = {}) {
    const origin = req.headers.get('origin');
    const allowedOrigins = options.allowedOrigins || ['*'];
    const allowAny = allowedOrigins.includes('*');
    const resolvedOrigin = allowAny ? '*' : origin && allowedOrigins.includes(origin) ? origin : '';

    const headers = new Headers({
        'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'authorization, apikey, x-client-info, content-type',
    });

    if (resolvedOrigin) headers.set('Access-Control-Allow-Origin', resolvedOrigin);
    if (options.allowCredentials) headers.set('Access-Control-Allow-Credentials', 'true');

    return { headers, allowed: allowAny || !origin || resolvedOrigin !== '' };
}

export function createCors(req: Request, options: CorsOptions = {}) {
    const { headers, allowed } = buildHeaders(req, options);

    return {
        blocked: !allowed,
        isOptions: req.method === 'OPTIONS',
        respond(status = 403, body = { error: 'CORS blocked' }) {
            return new Response(JSON.stringify(body), { status, headers });
        },
        preflight() {
            return new Response(null, { status: 204, headers });
        },
        json(body: unknown, status = 200) {
            const responseHeaders = new Headers(headers);
            responseHeaders.set('Content-Type', 'application/json');
            return new Response(JSON.stringify(body), { status, headers: responseHeaders });
        },
    };
}

