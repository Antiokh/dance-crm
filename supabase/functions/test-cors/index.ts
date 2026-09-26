import { createCors } from '../_shared/cors.ts';

function headersToObject(headers: Headers) {
    return Object.fromEntries(headers.entries());
}

async function readOptionalJson(req: Request) {
    if (req.method === 'GET' || req.method === 'HEAD') return null;

    const text = await req.text();
    if (!text) return null;

    return JSON.parse(text);
}

Deno.serve(async req => {
    const cors = createCors(req);

    if (cors.isOptions) return cors.preflight();
    if (cors.blocked) return cors.respond();

    try {
        const url = new URL(req.url);
        const body = await readOptionalJson(req);
        const query = Object.fromEntries(url.searchParams.entries());

        const response = {
            ok: true,
            method: req.method,
            query,
            body,
            headers: headersToObject(req.headers),
        };

        console.log('test-cors request:', response);

        return cors.json(response);
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return cors.json({ error: message }, 400);
    }
});

