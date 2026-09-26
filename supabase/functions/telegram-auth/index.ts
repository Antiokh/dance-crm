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

    const { data: existingDancer, error: dancerLookupError } = await supabase
      .from('dancer')
      .select('id, auth_user_id, telegram_id')
      .eq('telegram_id', telegramId)
      .maybeSingle()

    if (dancerLookupError) throw dancerLookupError

    let userId: string
    let created = false

    if (existingDancer?.auth_user_id) {
      userId = existingDancer.auth_user_id
      const { error: passwordError } = await supabase.rpc('update_user_password', {
        p_user_id: userId,
        p_new_password: authPassword,
      })
      if (passwordError) throw passwordError
    } else {
      const metadata = {
        telegram_id: telegramId,
        first_name: telegramUser.first_name ?? null,
        last_name: telegramUser.last_name ?? null,
        full_name: fullName || telegramUser.username || '',
        username: telegramUser.username ?? null,
        language_code: telegramUser.language_code ?? null,
      }

      const { data: newUserId, error: createError } = await supabase.rpc(
        'create_user_telegram_metadata',
        {
          telegram_id: telegramId,
          password: authPassword,
          user_meta_data: metadata,
        },
      )

      if (createError) throw createError
      if (!newUserId) throw new Error('Failed to create Supabase user')
      userId = newUserId
      created = true
    }

    const { data: ensuredDancer, error: ensureError } = await supabase.rpc(
      'ensure_dancer_exists',
      {
        p_user_id: userId,
      },
    )
    if (ensureError) throw ensureError
    if (!ensuredDancer?.id) throw new Error('Failed to ensure dancer profile')

    // Telegram identity fields are refreshed on every validated launch.
    const { error: syncDancerError } = await supabase
      .from('dancer')
      .update({
        telegram_username: telegramUser.username ?? null,
        first_name: telegramUser.first_name ?? null,
        last_name: telegramUser.last_name ?? null,
        lang_code: telegramUser.language_code ?? ensuredDancer.lang_code ?? 'en',
      })
      .eq('id', ensuredDancer.id)
    if (syncDancerError) throw syncDancerError

    const { data: dancer, error: dancerError } = await supabase
      .from('dancer')
      .select('id, auth_user_id, telegram_id, telegram_username, first_name, last_name, custom_name, lang_code, premium, primary_role')
      .eq('id', ensuredDancer.id)
      .single()
    if (dancerError) throw dancerError

    const { data: roleRows, error: rolesError } = await supabase
      .from('dancer_app_roles')
      .select('role')
      .eq('dancer_id', dancer.id)
    if (rolesError) throw rolesError

    return json({
      valid: true,
      created,
      auth_email: `${telegramId}@t.me`,
      auth_password: authPassword,
      dancer_id: dancer.id,
      profile: dancer,
      roles: (roleRows ?? []).map((row) => row.role),
    })
  } catch (error) {
    console.error('telegram-auth failed', error)
    return json({
      valid: false,
      error: error instanceof Error ? error.message : 'Internal Server Error',
    }, 500)
  }
})
