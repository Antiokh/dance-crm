import * as ed from '@noble/ed25519'

const TELEGRAM_PRODUCTION_PUBLIC_KEY_HEX = 'e7bf03a2fa4602af4580703d88dda5bb59f32ed8b02a56c187fe7d34caed242d'
const MAX_AUTH_AGE_SECONDS = 5 * 60
const MAX_FUTURE_SKEW_SECONDS = 30

export type ValidatedTelegramUser = {
  id: number
  first_name?: string
  last_name?: string
  username?: string
  language_code?: string
  photo_url?: string
}

export type TelegramValidationResult =
  | {
      valid: true
      authDate: number
      user: ValidatedTelegramUser
    }
  | {
      valid: false
      error: string
    }

export async function validateTelegramInitData(
  initData: string,
  botId: string,
): Promise<TelegramValidationResult> {
  if (!initData) return { valid: false, error: 'Missing initData' }
  if (!/^\d+$/.test(botId)) return { valid: false, error: 'Missing or invalid bot_id' }

  const params = new URLSearchParams(initData)
  const signatureValue = params.get('signature')
  if (!signatureValue) return { valid: false, error: 'Missing signature in initData' }

  const fields: Array<{ key: string; value: string }> = []
  const raw: Record<string, string> = {}

  for (const [key, value] of params.entries()) {
    if (key === 'signature' || key === 'hash') continue
    fields.push({ key, value })
    raw[key] = value
  }

  fields.sort((left, right) => left.key.localeCompare(right.key))

  const dataCheck = `${botId}:WebAppData\n${fields.map((field) => `${field.key}=${field.value}`).join('\n')}`
  const signature = base64UrlToBytes(signatureValue)
  const publicKey = hexToBytes(TELEGRAM_PRODUCTION_PUBLIC_KEY_HEX)
  const encoded = new TextEncoder().encode(dataCheck)
  const isValid = await ed.verifyAsync(signature, encoded, publicKey)

  if (!isValid) return { valid: false, error: 'Invalid Telegram signature' }

  const authDate = Number(raw.auth_date)
  const nowSeconds = Math.floor(Date.now() / 1000)
  const isFresh = Number.isSafeInteger(authDate)
    && authDate > 0
    && authDate >= nowSeconds - MAX_AUTH_AGE_SECONDS
    && authDate <= nowSeconds + MAX_FUTURE_SKEW_SECONDS

  if (!isFresh) return { valid: false, error: 'Expired or invalid auth_date' }
  if (!raw.user) return { valid: false, error: 'Missing Telegram user' }

  let user: ValidatedTelegramUser
  try {
    user = JSON.parse(raw.user)
  } catch {
    return { valid: false, error: 'Invalid Telegram user payload' }
  }

  if (!Number.isSafeInteger(Number(user.id))) {
    return { valid: false, error: 'Invalid Telegram user id' }
  }

  return { valid: true, authDate, user }
}

function hexToBytes(hex: string) {
  const bytes = new Uint8Array(hex.length / 2)
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16)
  }
  return bytes
}

function base64UrlToBytes(value: string) {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - value.length % 4) % 4)
  const binary = atob(base64)
  const out = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) out[index] = binary.charCodeAt(index)
  return out
}
