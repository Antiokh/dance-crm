import { optionalEnv } from '../_shared/env.ts';

function toAbsolutePath(path: string): string {
    if (/^(?:[A-Za-z]:\\|\/)/.test(path)) return path;
    const separator = Deno.build.os === 'windows' ? '\\' : '/';
    return `${Deno.cwd()}${separator}${path}`;
}

function parseEnvFile(content: string): Record<string, string> {
    const output: Record<string, string> = {};

    for (const rawLine of content.split(/\r?\n/)) {
        const line = rawLine.trim();
        if (!line || line.startsWith('#')) continue;

        const equalsIndex = line.indexOf('=');
        if (equalsIndex <= 0) continue;

        const key = line.slice(0, equalsIndex).trim();
        let value = line.slice(equalsIndex + 1).trim();

        if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
            const quote = value[0];
            value = value.slice(1, -1);

            if (quote === '"') {
                value = value
                    .replace(/\\n/g, '\n')
                    .replace(/\\r/g, '\r')
                    .replace(/\\t/g, '\t')
                    .replace(/\\"/g, '"')
                    .replace(/\\\\/g, '\\');
            }
        }

        output[key] = value;
    }

    return output;
}

Deno.serve(async () => {
    const envFilename = optionalEnv('DENO_ENV_FILE');
    let fileStatus = 'Not specified via DENO_ENV_FILE';

    if (envFilename) {
        const filePath = toAbsolutePath(envFilename);

        try {
            const fileContent = await Deno.readTextFile(filePath);
            const loaded = parseEnvFile(fileContent);

            for (const [key, value] of Object.entries(loaded)) {
                Deno.env.set(key, value);
            }

            fileStatus = `Successfully loaded from: ${filePath}`;
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            fileStatus = `Failed to load file at: ${filePath}. Error: ${message}`;
        }
    }

    return new Response(
        JSON.stringify(
            {
                env_file_status: fileStatus,
                variables_from_deno_env: Object.keys(Deno.env.toObject()).sort(),
            },
            null,
            2
        ),
        { headers: { 'Content-Type': 'application/json' } }
    );
});

