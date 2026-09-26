import { diffLines } from '@diff';

type DiffEntry = {
    type: '=' | '+' | '-';
    line: string;
};

function normalize(code: string): string {
    return code.replace(/\\n/g, '\n').replace(/\r\n/g, '\n').trim();
}

async function hashText(text: string): Promise<string> {
    const buffer = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buffer))
        .map(byte => byte.toString(16).padStart(2, '0'))
        .join('');
}

Deno.serve(async req => {
    try {
        const body = await req.json();
        const oldRaw = String(body.old ?? '');
        const newRaw = String(body.new ?? '');

        const oldNormalized = normalize(oldRaw);
        const newNormalized = normalize(newRaw);

        const oldHash = oldNormalized ? await hashText(oldNormalized) : null;
        const newHash = newNormalized ? await hashText(newNormalized) : null;

        if (oldHash === newHash) {
            return Response.json({
                changed: false,
                hash: newHash,
                stats: { added: 0, removed: 0 },
                diff: [],
            });
        }

        const parts = diffLines(oldNormalized, newNormalized);
        const diff: DiffEntry[] = [];
        let added = 0;
        let removed = 0;

        for (const part of parts) {
            const lines = part.value.split('\n').filter(line => line !== '');

            for (const line of lines) {
                if (part.added) {
                    diff.push({ type: '+', line });
                    added++;
                } else if (part.removed) {
                    diff.push({ type: '-', line });
                    removed++;
                } else {
                    diff.push({ type: '=', line });
                }
            }
        }

        return Response.json({
            changed: true,
            hash: newHash,
            stats: { added, removed },
            diff,
        });
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return Response.json({ error: message }, { status: 400 });
    }
});
