import { createCors } from '../_shared/cors.ts'
import { isLocalEnv, requireEnv } from '../_shared/env.ts'
import { supabaseService } from '../_shared/supabase.ts'

type DebugLogBody = {
  source?: string
  message?: string
  payload?: unknown
}

async function safeJson(req: Request): Promise<DebugLogBody> {
  const text = await req.text()
  return text ? JSON.parse(text) : {}
}

Deno.serve(async (req) => {
  const cors = createCors(req)

  if (cors.isOptions) return cors.preflight()
  if (cors.blocked) return cors.respond()

  const authorization = req.headers.get('authorization')

  if (!isLocalEnv()) {
    if (!authorization?.startsWith('Bearer ')) {
      return cors.json({ error: 'Missing authorization' }, 401)
    }

    const token = authorization.replace('Bearer ', '').trim()
    if (token !== requireEnv('SUPABASE_SERVICE_ROLE_KEY')) {
      return cors.json({ error: 'Forbidden' }, 403)
    }
  }

  try {
    const body = await safeJson(req)
    const source = body.source || 'unknown'
    const message = body.message || '(no message)'
    const payload = body.payload ?? null

    const { error } = await supabaseService().from('debug_events').insert({
      source,
      message,
      payload,
    })

    if (error) throw error
    return cors.json({ ok: true })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return cors.json({ error: message }, 400)
  }
})
