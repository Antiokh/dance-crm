import type { Session } from '@supabase/supabase-js'
import { loadMyDancerContext, parseDancerContext, type DancerContext } from './dancerContext'
import { supabase } from './supabase'
import {
  getNativeTelegramUser,
  getTmaRawInitData,
} from './tma'
import {
  getTelegramInitData,
  getTelegramUser,
} from './telegram'

type TelegramAuthResponse = {
  valid: boolean
  auth_email?: string
  auth_password?: string
  dancer_id?: string
  context?: unknown
  error?: string
}

export type AuthState =
  | {
      status: 'preview'
      session: null
      context: null
      error: null
    }
  | {
      status: 'authenticated'
      session: Session
      context: DancerContext
      error: null
    }
  | {
      status: 'error'
      session: null
      context: null
      error: string
    }

function currentInitData() {
  return getTmaRawInitData()?.trim() || getTelegramInitData().trim()
}

function currentTelegramUser() {
  return getNativeTelegramUser() ?? getTelegramUser()
}

export async function authenticateTelegram(): Promise<AuthState> {
  const initData = currentInitData()
  const telegramUser = currentTelegramUser()

  const { data: sessionData, error: sessionError } =
    await supabase.auth.getSession()

  if (sessionError) {
    return {
      status: 'error',
      session: null,
      context: null,
      error: sessionError.message,
    }
  }

  if (sessionData.session) {
    const sessionTelegramId =
      sessionData.session.user.user_metadata?.telegram_id

    const sameTelegramUser =
      !telegramUser ||
      String(sessionTelegramId ?? '') === String(telegramUser.id)

    if (sameTelegramUser) {
      try {
        return {
          status: 'authenticated',
          session: sessionData.session,
          context: await loadMyDancerContext(),
          error: null,
        }
      } catch {
        // Keep Dobri's behavior: stale app context falls through to a fresh
        // Telegram validation when raw initData is available.
      }
    }

    await supabase.auth.signOut().catch(() => undefined)
  }

  if (!initData) {
    return {
      status: 'preview',
      session: null,
      context: null,
      error: null,
    }
  }

  const botId = import.meta.env.VITE_TELEGRAM_BOT_ID?.trim()
  if (!botId || !/^\d+$/.test(botId)) {
    return {
      status: 'error',
      session: null,
      context: null,
      error: 'VITE_TELEGRAM_BOT_ID is not configured',
    }
  }

  try {
    const { data, error } =
      await supabase.functions.invoke<TelegramAuthResponse>(
        'telegram-auth',
        {
          body: {
            initData,
            bot_id: botId,
          },
        },
      )

    if (error) {
      throw new Error(await functionErrorMessage(error))
    }

    if (!data?.valid || !data.auth_email || !data.auth_password) {
      throw new Error(data?.error || 'Telegram authentication failed')
    }

    const { data: signInData, error: signInError } =
      await supabase.auth.signInWithPassword({
        email: data.auth_email,
        password: data.auth_password,
      })

    if (signInError) throw signInError
    if (!signInData.session) {
      throw new Error('Supabase session was not created')
    }

    return {
      status: 'authenticated',
      session: signInData.session,
      context: data.context
        ? parseDancerContext(data.context)
        : await loadMyDancerContext(),
      error: null,
    }
  } catch (error) {
    await supabase.auth.signOut().catch(() => undefined)

    let detail = errorMessage(error)
    if (detail === 'Expired or invalid auth_date') {
      const authDate = Number(
        new URLSearchParams(initData).get('auth_date'),
      )
      const nowSeconds = Math.floor(Date.now() / 1000)

      if (Number.isSafeInteger(authDate) && authDate > 0) {
        detail = `${detail} (age ${nowSeconds - authDate}s)`
      }
    }

    return {
      status: 'error',
      session: null,
      context: null,
      error: detail,
    }
  }
}

async function functionErrorMessage(error: unknown) {
  const fallback = errorMessage(error)
  const context = (error as { context?: Response } | null)?.context
  if (!context) return fallback

  try {
    const payload =
      await context.clone().json() as { error?: unknown }
    if (
      typeof payload?.error === 'string' &&
      payload.error.trim()
    ) {
      return payload.error
    }
  } catch {
    // Keep the Functions client error if the response is not JSON.
  }

  return fallback
}

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message

  if (typeof error === 'object' && error !== null) {
    const source = error as Record<string, unknown>
    if (typeof source.message === 'string') return source.message
    try {
      return JSON.stringify(source)
    } catch {
      return String(source)
    }
  }

  return String(error)
}
