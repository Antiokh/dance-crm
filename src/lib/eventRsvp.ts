import { supabase } from './supabase'
import { getTelegramStartParam } from './telegram'

export type EventRsvpResponse = 'going' | 'not_going'

export type EventRsvpResult = {
  event_id: string
  response: EventRsvpResponse | null
  role_id: number | null
  responded_at: string | null
  leader_going_count: number
  follower_going_count: number
  other_going_count: number
  going_count: number
  role_balance: number
}

export type EventRsvpIntent = {
  eventId: string
  response: EventRsvpResponse
  source: 'telegram_start_param' | 'web_query'
}

const EVENT_ID_PATTERN =
  '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}'

function rsvpResponse(value: unknown): EventRsvpResponse | null {
  return value === 'going' || value === 'not_going' ? value : null
}

function eventId(value: unknown) {
  if (typeof value !== 'string') return null
  return new RegExp(`^${EVENT_ID_PATTERN}$`).test(value) ? value.toLowerCase() : null
}

export function getEventRsvpIntent(): EventRsvpIntent | null {
  const startParam = getTelegramStartParam().trim()
  if (startParam) {
    const match = new RegExp(
      `^event_(${EVENT_ID_PATTERN})_(going|not_going)$`,
      'i',
    ).exec(startParam)

    if (match) {
      const parsedId = eventId(match[1])
      const response = rsvpResponse(match[2]?.toLowerCase())
      if (parsedId && response) {
        return {
          eventId: parsedId,
          response,
          source: 'telegram_start_param',
        }
      }
    }
  }

  const query = new URLSearchParams(window.location.search)
  const parsedId = eventId(query.get('event'))
  const response = rsvpResponse(query.get('rsvp'))

  if (!parsedId || !response) return null

  return {
    eventId: parsedId,
    response,
    source: 'web_query',
  }
}

export function telegramEventRsvpStartParam(
  eventIdValue: string,
  response: EventRsvpResponse,
) {
  const parsedId = eventId(eventIdValue)
  if (!parsedId) throw new Error('Invalid event id')
  return `event_${parsedId}_${response}`
}

function numberValue(value: unknown) {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0
}

export async function setEventRsvpResponse(
  eventIdValue: string,
  response: EventRsvpResponse,
): Promise<EventRsvpResult> {
  const { data, error } = await supabase.rpc('set_my_event_response', {
    p_event_id: eventIdValue,
    p_response: response,
  })

  if (error) throw error
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error('RSVP response is invalid')
  }

  const row = data as Record<string, unknown>
  const parsedEventId = eventId(row.event_id)
  const parsedResponse = rsvpResponse(row.response)

  if (!parsedEventId || !parsedResponse) {
    throw new Error('RSVP response is invalid')
  }

  return {
    event_id: parsedEventId,
    response: parsedResponse,
    role_id: typeof row.role_id === 'number' ? row.role_id : null,
    responded_at:
      typeof row.responded_at === 'string'
        ? row.responded_at
        : null,
    leader_going_count: numberValue(row.leader_going_count),
    follower_going_count: numberValue(row.follower_going_count),
    other_going_count: numberValue(row.other_going_count),
    going_count: numberValue(row.going_count),
    role_balance: numberValue(row.role_balance),
  }
}
