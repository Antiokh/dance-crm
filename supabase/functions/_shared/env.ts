export function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new Error(`${name} is not set`)
  return value
}

export function optionalEnv(name: string): string | undefined {
  const value = Deno.env.get(name)?.trim()
  return value || undefined
}
