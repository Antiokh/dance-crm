type EnvOptions = {
    defaultValue?: string;
    allowEmpty?: boolean;
    localDefault?: boolean;
};

const overrides: Record<string, string> = {};

export function isLocalEnv(): boolean {
    const env = Deno.env.get('ENV');
    if (env === 'local') return true;

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    return (
        supabaseUrl.startsWith('http://127.0.0.1:') ||
        supabaseUrl.startsWith('http://localhost:') ||
        supabaseUrl.startsWith('https://127.0.0.1:') ||
        supabaseUrl.startsWith('https://localhost:')
    );
}

function readEnv(name: string): string | undefined {
    if (overrides[name] != null) return overrides[name];

    const override = Deno.env.get(`OVERRIDE_${name}`);
    if (override != null) return override;

    return Deno.env.get(name);
}

export function setEnvOverride(name: string, value: string) {
    overrides[name] = value;
}

export function clearEnvOverride(name: string) {
    delete overrides[name];
}

export function requireEnv(name: string): string {
    const value = readEnv(name);
    if (value == null || value === '') {
        throw new Error(`${name} is not set`);
    }
    return value;
}

export function optionalEnv(name: string, options: EnvOptions = {}): string | undefined {
    const value = readEnv(name);
    if (value != null && (options.allowEmpty || value !== '')) return value;

    if (options.defaultValue != null) {
        if (!options.localDefault || isLocalEnv()) return options.defaultValue;
    }

    return undefined;
}

export function envBoolean(name: string, fallback?: boolean): boolean {
    const value = readEnv(name);
    if (value == null || value === '') {
        if (fallback != null) return fallback;
        throw new Error(`${name} is not set`);
    }

    const normalized = value.toLowerCase();
    if (normalized === 'true' || normalized === '1' || normalized === 'yes') return true;
    if (normalized === 'false' || normalized === '0' || normalized === 'no') return false;

    throw new Error(`${name} is not a valid boolean`);
}

export function envNumber(name: string, fallback?: number): number {
    const value = readEnv(name);
    if (value == null || value === '') {
        if (fallback != null) return fallback;
        throw new Error(`${name} is not set`);
    }

    const parsed = Number(value);
    if (Number.isNaN(parsed)) {
        throw new Error(`${name} is not a valid number`);
    }

    return parsed;
}
