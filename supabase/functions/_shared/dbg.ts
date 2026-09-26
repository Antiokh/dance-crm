import { edgeServiceFetch } from './edge.ts';

export function createDbg(notify = false) {
    return async function dbg(source: string, message: string, payload?: unknown) {
        try {
            await edgeServiceFetch('debug-log', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    source,
                    message,
                    payload,
                    notify,
                }),
            });
        } catch {
            // Logging should not break the caller.
        }
    };
}

