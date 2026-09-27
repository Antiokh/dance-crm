import { createCors } from '../_shared/cors.ts'
import { supabaseService } from '../_shared/supabase.ts'

const WORKER_ID = 'edge:social-publish-dispatch'
const LEASE_SECONDS = 180

type JsonRecord = Record<string, unknown>

type ClaimedJob = {
  job_id: string
  publication_id: string
  destination_key: string
  publisher: 'telegram_api' | 'threads_api' | 'instagram_api' | 'make_webhook'
  platform: string
  operation: 'publish' | 'edit'
  settings: JsonRecord | null
  publication_type: 'announcement' | 'updated' | 'cancelled' | 'rsvp_update'
  event_id: string
  payload: JsonRecord
  attempt_count: number
  max_attempts: number
  provider_progress: JsonRecord | null
}

type Destination = {
  key: string
  platform: string
  publisher: ClaimedJob['publisher']
  enabled: boolean
  settings: JsonRecord | null
}

type Attendee = {
  name: string
  role_id: number | null
}

type PublicationContext = {
  publication_id: string
  event_id: string
  publication_type: ClaimedJob['publication_type']
  version: number
  payload: JsonRecord
  event_state: {
    published: boolean
    cancelled_at: string | null
  }
  balance: {
    leader: number
    follower: number
    other: number
    total: number
  }
  attendees: Attendee[]
  telegram_message: {
    message_id: string
    url: string | null
    provider_response: JsonRecord | null
  } | null
}

type RenderedCopy = {
  title: string
  plain: string
  html: string
  goingUrl: string | null
  notGoingUrl: string | null
}

type PublishResult = {
  external_post_id: string | null
  external_post_url: string | null
  provider_response: JsonRecord
}

class TerminalPublishError extends Error {
  terminal = true
}

function record(value: unknown): JsonRecord {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as JsonRecord
    : {}
}

function text(value: unknown) {
  return value == null ? '' : String(value)
}

function optionalText(value: unknown) {
  const valueText = text(value).trim()
  return valueText || null
}

function numberValue(value: unknown) {
  const valueNumber = Number(value)
  return Number.isFinite(valueNumber) ? valueNumber : 0
}

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
}

function errorMessage(reason: unknown) {
  return reason instanceof Error ? reason.message : String(reason)
}

function truncateText(value: string | null, maxLength: number) {
  if (!value || value.length <= maxLength) return value
  return `${value.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`
}

function requireEnv(name: string) {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new TerminalPublishError(`${name} is not configured`)
  return value
}

function optionalEnv(name: string) {
  const value = Deno.env.get(name)?.trim()
  return value || null
}

function safeEqual(left: string, right: string) {
  const leftBytes = new TextEncoder().encode(left)
  const rightBytes = new TextEncoder().encode(right)
  if (leftBytes.length !== rightBytes.length) return false

  let diff = 0
  for (let index = 0; index < leftBytes.length; index += 1) {
    diff |= leftBytes[index] ^ rightBytes[index]
  }
  return diff === 0
}

async function debug(message: string, payload: unknown) {
  try {
    await supabaseService()
      .from('debug_events')
      .insert({
        source: 'social-publish-dispatch',
        message,
        payload,
      })
  } catch {
    // Diagnostics must never break delivery.
  }
}

async function expectedSecret() {
  const { data, error } = await supabaseService()
    .rpc('social_get_dispatch_secret')

  if (error) throw error
  return typeof data === 'string' ? data : ''
}

async function claimJobs(): Promise<ClaimedJob[]> {
  const { data, error } = await supabaseService()
    .rpc('social_claim_publication_jobs', {
      p_worker: WORKER_ID,
      p_limit: 8,
      p_lease_seconds: LEASE_SECONDS,
    })

  if (error) throw error
  return Array.isArray(data) ? data as ClaimedJob[] : []
}

async function loadDestination(key: string): Promise<Destination> {
  const { data, error } = await supabaseService()
    .from('social_destinations')
    .select('key, platform, publisher, enabled, settings')
    .eq('key', key)
    .single()

  if (error) throw error
  return data as Destination
}

async function loadContext(publicationId: string): Promise<PublicationContext> {
  const { data, error } = await supabaseService()
    .rpc('social_get_event_publication_context', {
      p_publication_id: publicationId,
    })

  if (error) throw error
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error('Social publication context is missing')
  }

  const source = data as JsonRecord
  const balance = record(source.balance)
  const eventState = record(source.event_state)
  const telegramMessage = record(source.telegram_message)

  return {
    publication_id: String(source.publication_id),
    event_id: String(source.event_id),
    publication_type: source.publication_type as PublicationContext['publication_type'],
    version: numberValue(source.version),
    payload: record(source.payload),
    event_state: {
      published: eventState.published === true,
      cancelled_at: optionalText(eventState.cancelled_at),
    },
    balance: {
      leader: numberValue(balance.leader),
      follower: numberValue(balance.follower),
      other: numberValue(balance.other),
      total: numberValue(balance.total),
    },
    attendees: Array.isArray(source.attendees)
      ? source.attendees.map((value) => {
          const item = record(value)
          return {
            name: text(item.name).trim() || 'Танцор',
            role_id:
              typeof item.role_id === 'number'
                ? item.role_id
                : null,
          }
        })
      : [],
    telegram_message:
      optionalText(telegramMessage.message_id)
        ? {
            message_id: text(telegramMessage.message_id),
            url: optionalText(telegramMessage.url),
            provider_response: record(telegramMessage.provider_response),
          }
        : null,
  }
}

async function markStarted(
  job: ClaimedJob,
  progress: JsonRecord = {},
) {
  const { data, error } = await supabaseService()
    .rpc('social_mark_publish_started', {
      p_job_id: job.job_id,
      p_worker: WORKER_ID,
      p_progress: progress,
    })

  if (error) throw error
  if (data !== true) {
    throw new Error('Social publication lease is no longer active')
  }
}

async function patchProgress(job: ClaimedJob, progress: JsonRecord) {
  const { data, error } = await supabaseService()
    .rpc('social_patch_job_progress', {
      p_job_id: job.job_id,
      p_worker: WORKER_ID,
      p_progress: progress,
    })

  if (error) throw error
  if (data !== true) {
    throw new Error('Social publication lease is no longer active')
  }
}

async function markSuccess(job: ClaimedJob, result: PublishResult) {
  const { data, error } = await supabaseService()
    .rpc('social_mark_publication_success', {
      p_job_id: job.job_id,
      p_worker: WORKER_ID,
      p_external_post_id: result.external_post_id,
      p_external_post_url: result.external_post_url,
      p_provider_response: result.provider_response,
    })

  if (error) throw error
  if (data !== true) throw new Error('Could not mark social publication success')
}

async function markFailure(
  job: ClaimedJob,
  reason: unknown,
  terminal: boolean,
  retryAfterSeconds: number,
  providerResponse: JsonRecord = {},
) {
  const { data, error } = await supabaseService()
    .rpc('social_mark_publication_failure', {
      p_job_id: job.job_id,
      p_worker: WORKER_ID,
      p_error: errorMessage(reason),
      p_retry_after_seconds: retryAfterSeconds,
      p_provider_response: providerResponse,
      p_terminal: terminal,
    })

  if (error) throw error
  if (data !== true) throw new Error('Could not mark social publication failure')
}

function botUsername(destination: Destination) {
  const settings = record(destination.settings)
  return (
    optionalText(settings.bot_username)
    ?? optionalEnv('TELEGRAM_APP_BOT_USERNAME')
    ?? optionalEnv('DANCE_APP_BOT_USERNAME')
  )?.replace(/^@/, '') ?? null
}

function eventRsvpUrl(
  destination: Destination,
  eventId: string,
  response: 'going' | 'not_going',
) {
  const username = botUsername(destination)
  if (!username) return null
  return `https://t.me/${username}?startapp=${encodeURIComponent(
    `event_${eventId}_${response}`,
  )}`
}

function styleTitle(payload: JsonRecord) {
  const style = record(payload.style)
  return (
    optionalText(style.title_ru)
    ?? optionalText(style.title_en)
    ?? optionalText(style.title_sr)
  )
}

function venueText(payload: JsonRecord) {
  const venue = record(payload.venue)
  const name = optionalText(venue.name)
  const address = optionalText(venue.address)
  return [name, address].filter(Boolean).join(' · ') || null
}

function belgradeDateTime(value: unknown) {
  const raw = optionalText(value)
  if (!raw) return null

  const date = new Date(raw)
  if (!Number.isFinite(date.getTime())) return null

  return new Intl.DateTimeFormat('ru-RU', {
    day: 'numeric',
    month: 'long',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Europe/Belgrade',
  }).format(date)
}

function attendeeLabel(attendee: Attendee) {
  if (attendee.role_id === 1) return `${attendee.name} — Leader`
  if (attendee.role_id === 2) return `${attendee.name} — Follower`
  return attendee.name
}

function attendeeLines(attendees: Attendee[], html: boolean) {
  const maxShown = 40
  const shown = attendees.slice(0, maxShown)
  const lines = shown.map((attendee) => {
    const label = attendeeLabel(attendee)
    return `• ${html ? escapeHtml(label) : label}`
  })

  if (attendees.length > maxShown) {
    lines.push(`…и ещё ${attendees.length - maxShown}`)
  }

  return lines
}

function renderCopy(
  destination: Destination,
  context: PublicationContext,
): RenderedCopy {
  const payload = context.payload
  const title = optionalText(payload.title) ?? 'Событие'
  const description = truncateText(
    optionalText(payload.description),
    destination.publisher === 'threads_api'
      ? 180
      : destination.publisher === 'telegram_api'
        ? 900
        : 1200,
  )
  const startsAt = belgradeDateTime(payload.starts_at)
  const endsAt = belgradeDateTime(payload.ends_at)
  const venue = venueText(payload)
  const style = styleTitle(payload)

  const goingUrl = eventRsvpUrl(destination, context.event_id, 'going')
  const notGoingUrl = eventRsvpUrl(destination, context.event_id, 'not_going')

  const prefix =
    context.publication_type === 'cancelled'
      ? '❌'
      : context.publication_type === 'updated'
        ? '🔄'
        : '💃'

  const statusTitle =
    context.publication_type === 'cancelled'
      ? 'Событие отменено'
      : context.publication_type === 'updated'
        ? 'Событие обновлено'
        : title

  const plainLines = [
    `${prefix} ${statusTitle}`,
    context.publication_type === 'announcement' ? null : title,
    '',
    startsAt ? `🗓 ${startsAt}${endsAt ? ` — ${endsAt}` : ''}` : null,
    venue ? `📍 ${venue}` : null,
    style ? `🎵 ${style}` : null,
    description ? '' : null,
    description,
  ].filter((line): line is string => line !== null)

  if (context.publication_type !== 'cancelled') {
    plainLines.push(
      '',
      `👥 Идут: ${context.balance.total} · Leader ${context.balance.leader} · Follower ${context.balance.follower}`,
    )
  }

  if (
    destination.publisher === 'telegram_api'
    && context.publication_type !== 'cancelled'
    && context.attendees.length > 0
  ) {
    plainLines.push('', 'Кто идёт:', ...attendeeLines(context.attendees, false))
  }

  if (context.publication_type !== 'cancelled' && goingUrl && notGoingUrl) {
    plainLines.push(
      '',
      `Я приду: ${goingUrl}`,
      `Я не приду: ${notGoingUrl}`,
    )
  }

  const htmlLines = [
    `${prefix} <b>${escapeHtml(statusTitle)}</b>`,
    context.publication_type === 'announcement'
      ? null
      : escapeHtml(title),
    '',
    startsAt
      ? `🗓 <b>${escapeHtml(startsAt)}${endsAt ? ` — ${escapeHtml(endsAt)}` : ''}</b>`
      : null,
    venue ? `📍 ${escapeHtml(venue)}` : null,
    style ? `🎵 ${escapeHtml(style)}` : null,
    description ? '' : null,
    description ? escapeHtml(description) : null,
  ].filter((line): line is string => line !== null)

  if (context.publication_type !== 'cancelled') {
    htmlLines.push(
      '',
      `👥 Идут: <b>${context.balance.total}</b> · Leader <b>${context.balance.leader}</b> · Follower <b>${context.balance.follower}</b>`,
    )
  }

  if (
    destination.publisher === 'telegram_api'
    && context.publication_type !== 'cancelled'
    && context.attendees.length > 0
  ) {
    htmlLines.push('', '<b>Кто идёт:</b>', ...attendeeLines(context.attendees, true))
  }

  return {
    title,
    plain: plainLines.join('\n'),
    html: htmlLines.join('\n'),
    goingUrl,
    notGoingUrl,
  }
}

function telegramReplyMarkup(copy: RenderedCopy) {
  if (!copy.goingUrl || !copy.notGoingUrl) {
    throw new TerminalPublishError(
      'Telegram Mini App bot username is not configured',
    )
  }

  return {
    inline_keyboard: [[
      { text: '✅ Я приду', url: copy.goingUrl },
      { text: '❌ Я не приду', url: copy.notGoingUrl },
    ]],
  }
}

function telegramChatId(destination: Destination) {
  const settings = record(destination.settings)
  return (
    optionalText(settings.chat_id)
    ?? optionalEnv('TELEGRAM_SOCIAL_CHAT_ID')
  )
}

async function telegramRequest(
  method: 'sendMessage' | 'editMessageText',
  body: JsonRecord,
) {
  const token = requireEnv('TELEGRAM_BOT_TOKEN')
  let response: Response

  try {
    response = await fetch(
      `https://api.telegram.org/bot${token}/${method}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      },
    )
  } catch (reason) {
    throw new TerminalPublishError(
      `Telegram request outcome is ambiguous: ${errorMessage(reason)}`,
    )
  }

  const payload = await response.json().catch(() => null) as {
    ok?: boolean
    description?: string
    result?: { message_id?: number }
  } | null

  if (!response.ok || !payload?.ok) {
    throw new Error(
      `Telegram API failed: ${payload?.description || `HTTP ${response.status}`}`,
    )
  }

  return payload
}

async function publishTelegram(
  job: ClaimedJob,
  destination: Destination,
  context: PublicationContext,
  copy: RenderedCopy,
): Promise<PublishResult> {
  if (job.operation === 'edit') {
    const target = context.telegram_message
    const chatId =
      optionalText(record(target?.provider_response).chat_id)
      ?? telegramChatId(destination)

    if (!target?.message_id || !chatId) {
      throw new TerminalPublishError(
        'Telegram RSVP update has no published message target',
      )
    }

    await markStarted(job, {
      provider: 'telegram',
      operation: 'edit',
      safe_retry: true,
      message_id: target.message_id,
    })

    const payload = await telegramRequest('editMessageText', {
      chat_id: chatId,
      message_id: Number(target.message_id),
      text: copy.html,
      parse_mode: 'HTML',
      disable_web_page_preview: true,
      reply_markup: telegramReplyMarkup(copy),
    })

    return {
      external_post_id: target.message_id,
      external_post_url: target.url,
      provider_response: {
        telegram: payload,
        chat_id: chatId,
        operation: 'edit',
      },
    }
  }

  const chatId = telegramChatId(destination)
  if (!chatId) {
    throw new TerminalPublishError(
      'TELEGRAM_SOCIAL_CHAT_ID or destination settings.chat_id is not configured',
    )
  }

  await markStarted(job, {
    provider: 'telegram',
    operation: 'publish',
    safe_retry: false,
  })

  const payload = await telegramRequest('sendMessage', {
    chat_id: chatId,
    text: copy.html,
    parse_mode: 'HTML',
    disable_web_page_preview: true,
    reply_markup: telegramReplyMarkup(copy),
  })

  const messageId = payload.result?.message_id != null
    ? String(payload.result.message_id)
    : null

  if (!messageId) {
    throw new TerminalPublishError(
      'Telegram sendMessage returned no message id',
    )
  }

  const settings = record(destination.settings)
  const username = (
    optionalText(settings.chat_username)
    ?? optionalEnv('TELEGRAM_SOCIAL_CHAT_USERNAME')
  )?.replace(/^@/, '') ?? null

  return {
    external_post_id: messageId,
    external_post_url:
      username
        ? `https://t.me/${username}/${messageId}`
        : null,
    provider_response: {
      telegram: payload,
      chat_id: chatId,
      operation: 'publish',
    },
  }
}

function threadsUrl(path: string) {
  const url = new URL(
    `https://graph.threads.net/v1.0/${path.replace(/^\/+/, '')}`,
  )
  url.searchParams.set('access_token', requireEnv('THREADS_ACCESS_TOKEN'))
  return url
}

async function threadsRequest(
  path: string,
  init: {
    method?: 'GET' | 'POST'
    body?: JsonRecord
    fields?: string
  } = {},
) {
  const url = threadsUrl(path)
  if (init.fields) url.searchParams.set('fields', init.fields)

  const response = await fetch(url, {
    method: init.method ?? 'GET',
    headers: init.body ? { 'Content-Type': 'application/json' } : undefined,
    body: init.body ? JSON.stringify(init.body) : undefined,
  })

  const raw = await response.text()
  let payload: JsonRecord = {}
  try {
    payload = raw ? JSON.parse(raw) as JsonRecord : {}
  } catch {
    payload = { raw }
  }

  if (!response.ok) {
    const apiError = record(payload.error)
    throw new Error(
      `Threads API failed: ${optionalText(apiError.message) || response.statusText}`,
    )
  }

  return payload
}

async function waitThreadsContainer(creationId: string) {
  for (let index = 0; index < 20; index += 1) {
    if (index > 0) {
      await new Promise((resolve) => setTimeout(resolve, 2000))
    }

    const status = await threadsRequest(creationId, {
      fields: 'id,status,error_message',
    })

    if (status.status === 'FINISHED') return status
    if (status.status === 'ERROR' || status.error_message) {
      throw new Error(
        `Threads container failed: ${text(status.error_message || status.status)}`,
      )
    }
  }

  throw new Error('Threads container timed out')
}

async function publishThreads(
  job: ClaimedJob,
  copy: RenderedCopy,
): Promise<PublishResult> {
  const userId = requireEnv('THREADS_USER_ID')

  const created = await threadsRequest(`${userId}/threads`, {
    method: 'POST',
    body: {
      media_type: 'TEXT',
      text: copy.plain,
    },
  })

  const creationId = optionalText(created.id)
  if (!creationId) {
    throw new Error('Threads did not return a creation id')
  }

  await waitThreadsContainer(creationId)
  await markStarted(job, {
    provider: 'threads',
    creation_id: creationId,
    safe_retry: false,
  })

  let published: JsonRecord
  try {
    published = await threadsRequest(`${userId}/threads_publish`, {
      method: 'POST',
      body: { creation_id: creationId },
    })
  } catch (reason) {
    throw new TerminalPublishError(
      `Threads publish outcome is ambiguous: ${errorMessage(reason)}`,
    )
  }

  const postId = optionalText(published.id)
  if (!postId) {
    throw new TerminalPublishError(
      'Threads publish returned no post id',
    )
  }

  let details: JsonRecord = {}
  try {
    details = await threadsRequest(postId, {
      fields: 'id,permalink,text,timestamp,username',
    })
  } catch {
    details = {}
  }

  return {
    external_post_id: postId,
    external_post_url: optionalText(details.permalink),
    provider_response: {
      creation_id: creationId,
      publish: published,
      details,
    },
  }
}

function instagramAccessToken() {
  return requireEnv('INSTAGRAM_ACCESS_TOKEN')
}

function instagramUserId() {
  return requireEnv('INSTAGRAM_USER_ID')
}

async function instagramPost(
  path: string,
  params: Record<string, string>,
) {
  const body = new URLSearchParams({
    ...params,
    access_token: instagramAccessToken(),
  })

  const response = await fetch(
    `https://graph.instagram.com/v26.0/${path}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
    },
  )

  const raw = await response.text()
  let payload: JsonRecord = {}
  try {
    payload = raw ? JSON.parse(raw) as JsonRecord : {}
  } catch {
    payload = { raw }
  }

  if (!response.ok) {
    throw new Error(
      `Instagram API failed: ${JSON.stringify(payload)}`,
    )
  }

  return payload
}

async function instagramGet(path: string, fields: string) {
  const url = new URL(`https://graph.instagram.com/v26.0/${path}`)
  url.searchParams.set('fields', fields)
  url.searchParams.set('access_token', instagramAccessToken())

  const response = await fetch(url)
  const raw = await response.text()
  let payload: JsonRecord = {}

  try {
    payload = raw ? JSON.parse(raw) as JsonRecord : {}
  } catch {
    payload = { raw }
  }

  if (!response.ok) {
    throw new Error(
      `Instagram read failed: ${JSON.stringify(payload)}`,
    )
  }

  return payload
}

async function waitInstagramContainer(creationId: string) {
  for (let index = 0; index < 20; index += 1) {
    if (index > 0) {
      await new Promise((resolve) => setTimeout(resolve, 3000))
    }

    const status = await instagramGet(
      creationId,
      'id,status_code,status',
    )
    const code =
      optionalText(status.status_code)
      ?? optionalText(status.status)

    if (code === 'FINISHED' || code === 'PUBLISHED') return status
    if (code === 'ERROR' || code === 'EXPIRED') {
      throw new Error(
        `Instagram container failed: ${JSON.stringify(status)}`,
      )
    }
  }

  throw new Error('Instagram container timed out')
}

function instagramImage(context: PublicationContext, destination: Destination) {
  const settings = record(destination.settings)
  return (
    optionalText(context.payload.announcement_image_url)
    ?? optionalText(settings.image_url)
    ?? optionalEnv('INSTAGRAM_SOCIAL_IMAGE_URL')
  )
}

async function publishInstagram(
  job: ClaimedJob,
  destination: Destination,
  context: PublicationContext,
  copy: RenderedCopy,
): Promise<PublishResult> {
  const imageUrl = instagramImage(context, destination)
  if (!imageUrl) {
    throw new TerminalPublishError(
      'Instagram announcement requires announcement_image_url or INSTAGRAM_SOCIAL_IMAGE_URL',
    )
  }

  const created = await instagramPost(
    `${instagramUserId()}/media`,
    {
      image_url: imageUrl,
      caption: copy.plain,
    },
  )

  const creationId = optionalText(created.id)
  if (!creationId) {
    throw new Error('Instagram did not return a creation id')
  }

  await waitInstagramContainer(creationId)
  await markStarted(job, {
    provider: 'instagram',
    creation_id: creationId,
    image_url: imageUrl,
    safe_retry: false,
  })

  let published: JsonRecord
  try {
    published = await instagramPost(
      `${instagramUserId()}/media_publish`,
      { creation_id: creationId },
    )
  } catch (reason) {
    throw new TerminalPublishError(
      `Instagram publish outcome is ambiguous: ${errorMessage(reason)}`,
    )
  }

  const mediaId = optionalText(published.id)
  if (!mediaId) {
    throw new TerminalPublishError(
      'Instagram publish returned no media id',
    )
  }

  let details: JsonRecord = {}
  try {
    details = await instagramGet(
      mediaId,
      'id,permalink,media_type,timestamp,username',
    )
  } catch {
    details = {}
  }

  return {
    external_post_id: mediaId,
    external_post_url: optionalText(details.permalink),
    provider_response: {
      creation_id: creationId,
      image_url: imageUrl,
      publish: published,
      details,
    },
  }
}

function envKeySegment(value: string) {
  return value
    .replace(/[^a-zA-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toUpperCase()
}

async function publishMake(
  job: ClaimedJob,
  destination: Destination,
  context: PublicationContext,
  copy: RenderedCopy,
): Promise<PublishResult> {
  const settings = record(destination.settings)
  const destinationWebhook = optionalEnv(
    `MAKE_${envKeySegment(destination.key)}_WEBHOOK_URL`,
  )
  const webhookUrl =
    optionalText(settings.webhook_url)
    ?? destinationWebhook
    ?? optionalEnv('MAKE_SOCIAL_PUBLISHING_WEBHOOK_URL')
    ?? optionalEnv('MAKE_SOCIAL_WEBHOOK_URL')

  if (!webhookUrl) {
    throw new TerminalPublishError(
      'MAKE_SOCIAL_PUBLISHING_WEBHOOK_URL is not configured',
    )
  }

  await markStarted(job, {
    provider: 'make_webhook',
    safe_retry: false,
  })

  let response: Response
  try {
    response = await fetch(webhookUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        destination: 'social_publishing',
        destination_key: destination.key,
        platform: destination.platform,
        job_id: job.job_id,
        post_id: context.event_id,
        variant_id: context.publication_id,
        idempotency_key: `${job.publication_id}:${destination.key}`,
        title: copy.title,
        source_url: copy.goingUrl ?? copy.notGoingUrl,
        text: copy.plain,
        html: copy.html,
        media: {
          mode: optionalText(context.payload.announcement_image_url)
            ? 'photo'
            : 'link',
          image_url: optionalText(context.payload.announcement_image_url),
        },
        metadata: {
          publication_type: context.publication_type,
          publication_version: context.version,
        },
        event: {
          ...context.payload,
          balance: context.balance,
          attendees: context.attendees,
        },
        actions: {
          going_url: copy.goingUrl,
          not_going_url: copy.notGoingUrl,
        },
      }),
    })
  } catch (reason) {
    throw new TerminalPublishError(
      `Make webhook outcome is ambiguous: ${errorMessage(reason)}`,
    )
  }

  const raw = await response.text()
  let payload: JsonRecord = {}
  try {
    payload = raw ? JSON.parse(raw) as JsonRecord : {}
  } catch {
    payload = { raw_response: raw }
  }

  if (!response.ok) {
    throw new TerminalPublishError(
      `Make social webhook failed after request: ${response.status} ${response.statusText}`,
    )
  }

  return {
    external_post_id:
      optionalText(payload.external_post_id)
      ?? optionalText(payload.post_id),
    external_post_url:
      optionalText(payload.external_post_url)
      ?? optionalText(payload.url),
    provider_response: {
      make_response: payload,
    },
  }
}

async function publishJob(
  job: ClaimedJob,
  destination: Destination,
  context: PublicationContext,
  copy: RenderedCopy,
) {
  if (context.publication_type === 'cancelled') {
    if (context.event_state.cancelled_at === null) {
      throw new TerminalPublishError(
        'Cancellation publication was superseded because the event is active again',
      )
    }
  } else if (
    !context.event_state.published
    || context.event_state.cancelled_at !== null
  ) {
    throw new TerminalPublishError(
      'Event is no longer publishable',
    )
  }

  if (!destination.enabled) {
    throw new TerminalPublishError(
      `Destination ${destination.key} is disabled`,
    )
  }

  if (destination.publisher === 'telegram_api') {
    return publishTelegram(job, destination, context, copy)
  }

  if (job.operation === 'edit') {
    throw new TerminalPublishError(
      `Publisher ${destination.publisher} does not support edit jobs`,
    )
  }

  if (destination.publisher === 'threads_api') {
    return publishThreads(job, copy)
  }

  if (destination.publisher === 'instagram_api') {
    return publishInstagram(job, destination, context, copy)
  }

  if (destination.publisher === 'make_webhook') {
    return publishMake(job, destination, context, copy)
  }

  throw new TerminalPublishError(
    `Unsupported social publisher: ${destination.publisher}`,
  )
}

function isRateLimitError(reason: unknown) {
  return /(^|[\s:])429($|[\s:])|rate limit|too many requests|quota exceeded|try again later|application request limit reached|user request limit reached/i
    .test(errorMessage(reason))
}

function retryAfterSeconds(reason: unknown) {
  const match = errorMessage(reason)
    .match(/retry[-_ ]after[^0-9]*(\d{1,6})/i)

  return match ? Number(match[1]) : 15 * 60
}

Deno.serve(async (request) => {
  const cors = createCors(request)

  if (cors.isOptions) return cors.preflight()
  if (cors.blocked) return cors.respond()

  if (request.method !== 'POST') {
    return cors.json({ error: 'Method not allowed' }, 405)
  }

  try {
    const provided =
      request.headers.get('x-dance-social-secret')?.trim() ?? ''
    const expected = await expectedSecret()

    if (!provided || !expected || !safeEqual(provided, expected)) {
      return cors.json({ error: 'Forbidden' }, 403)
    }

    const jobs = await claimJobs()
    await debug('queue_claimed', {
      claimed: jobs.map((job) => ({
        job_id: job.job_id,
        publication_id: job.publication_id,
        destination_key: job.destination_key,
        operation: job.operation,
        attempt_count: job.attempt_count,
      })),
    })

    const results: JsonRecord[] = []

    for (const job of jobs) {
      try {
        const [context, destination] = await Promise.all([
          loadContext(job.publication_id),
          loadDestination(job.destination_key),
        ])

        const copy = renderCopy(destination, context)
        const published = await publishJob(
          job,
          destination,
          context,
          copy,
        )

        await markSuccess(job, published)
        await debug('delivery_sent', {
          job_id: job.job_id,
          publication_id: job.publication_id,
          destination_key: job.destination_key,
          operation: job.operation,
          external_post_id: published.external_post_id,
          external_post_url: published.external_post_url,
        })

        results.push({
          job_id: job.job_id,
          destination_key: job.destination_key,
          status: 'published',
          external_post_url: published.external_post_url,
        })
      } catch (reason) {
        const terminal =
          reason instanceof TerminalPublishError
          || Boolean(
            reason
            && typeof reason === 'object'
            && (reason as { terminal?: unknown }).terminal === true
          )
        const rateLimited = isRateLimitError(reason)
        const retrySeconds =
          rateLimited ? retryAfterSeconds(reason) : 15 * 60

        try {
          await markFailure(
            job,
            reason,
            terminal,
            retrySeconds,
            {
              error: errorMessage(reason),
              terminal,
              rate_limited: rateLimited,
            },
          )
        } catch (markReason) {
          await debug('mark_failure_failed', {
            job_id: job.job_id,
            original_error: errorMessage(reason),
            mark_error: errorMessage(markReason),
          })
        }

        await debug(
          terminal ? 'delivery_failed' : 'delivery_retry',
          {
            job_id: job.job_id,
            publication_id: job.publication_id,
            destination_key: job.destination_key,
            operation: job.operation,
            error: errorMessage(reason),
            terminal,
            retry_after_seconds: retrySeconds,
          },
        )

        results.push({
          job_id: job.job_id,
          destination_key: job.destination_key,
          status: terminal ? 'dead' : 'retry',
          error: errorMessage(reason),
        })
      }
    }

    return cors.json({
      ok: true,
      claimed: jobs.length,
      results,
    })
  } catch (reason) {
    await debug('request_failed', {
      error: errorMessage(reason),
    })

    return cors.json({
      error: errorMessage(reason),
    }, 500)
  }
})
