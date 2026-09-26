import { createClient } from '@supabase'
import { requireEnv } from '../_shared/env.ts'
import { validateTelegramInitData } from '../_shared/telegramInitData.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function generateAuthPassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ valid: false, error: 'Method not allowed' }, 405)

  try {
    const { initData, bot_id } = await request.json()
    const validation = await validateTelegramInitData(initData, String(bot_id ?? ''))
    if (!validation.valid) return json(validation, 400)

    const supabase = createClient(
      requireEnv('SUPABASE_URL'),
      requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    )

    const telegramUser = validation.user
    const telegramId = Number(telegramUser.id)
    const fullName = [telegramUser.first_name, telegramUser.last_name].filter(Boolean).join(' ')

    // This password exists only to bridge a validated Telegram launch into a
    // normal Supabase Auth session. It is rotated on every validated login and
    // returned once to the client for the immediate signInWithPassword call.
    const authPassword = generateAuthPassword()

    const metadata = {
      telegram_id: telegramId,
      first_name: telegramUser.first_name ?? null,
      last_name: telegramUser.last_name ?? null,
      full_name: fullName || telegramUser.username || '',
      username: telegramUser.username ?? null,
      language_code: telegramUser.language_code ?? null,
    }

    const { data: bootstrap, error: bootstrapError } = await supabase.rpc(
      'telegram_auth_bootstrap',
      {
        p_telegram_id: telegramId,
        p_password: authPassword,
        p_user_meta_data: metadata,
      },
    )

    if (bootstrapError) throw bootstrapError
    if (!bootstrap || typeof bootstrap !== 'object') {
      throw new Error('Telegram auth bootstrap returned no context')
    }

    return json({
      valid: true,
      auth_password: authPassword,
      ...bootstrap,
    })
  } catch (error) {
    console.error('telegram-auth failed', error)
    return json({
      valid: false,
      error: error instanceof Error ? error.message : 'Internal Server Error',
    }, 500)
  }
})
