import { loadQuickAttendState } from './quickAttend'
import { supabase } from './supabase'

export type HomeVenue = {
  id: string
  name: string
  address: string | null
  latitude: number | null
  longitude: number | null
}

export type HomeStyle = {
  id: number
  title_en: string | null
  title_ru: string | null
  title_sr: string | null
  is_partner_dance: boolean
}

export type DanceEvent = {
  id: string
  event_type: 'party' | 'open_class'
  title: string
  description: string | null
  starts_at: string
  ends_at: string | null
  venue: HomeVenue | null
  style: HomeStyle | null
  attending: boolean
}

export type GroupClass = {
  id: string
  starts_at: string
  ends_at: string
  visibility: 'public' | 'members' | 'hidden'
  group_id: string
  group_title: string
  group_level: string | null
  style: HomeStyle
  venue: HomeVenue | null
  booking_status: 'booked' | 'waitlisted' | null
  booking_id: string | null
  booking_role_id: number | null
  role_balance: {
    leader: number
    follower: number
  } | null
}

export type AttentionItem = {
  id: string
  title: string
  body: string | null
  priority: number
  event: DanceEvent | null
}

export type DancerHomeFeed = {
  attention: AttentionItem[]
  today_events: DanceEvent[]
  today_classes: GroupClass[]
  events: DanceEvent[]
  classes: GroupClass[]
}

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function nullableString(value: unknown) {
  return typeof value === 'string' ? value : null
}

function venue(value: unknown): HomeVenue | null {
  const source = object(value)
  if (!source || typeof source.id !== 'string' || typeof source.name !== 'string') {
    return null
  }

  return {
    id: source.id,
    name: source.name,
    address: nullableString(source.address),
    latitude: typeof source.latitude === 'number' ? source.latitude : null,
    longitude: typeof source.longitude === 'number' ? source.longitude : null,
  }
}

function style(value: unknown): HomeStyle | null {
  const source = object(value)
  if (!source || typeof source.id !== 'number') return null

  return {
    id: source.id,
    title_en: nullableString(source.title_en),
    title_ru: nullableString(source.title_ru),
    title_sr: nullableString(source.title_sr),
    is_partner_dance: source.is_partner_dance === true,
  }
}

function parseEvent(value: unknown): DanceEvent | null {
  const source = object(value)
  const eventType = source?.event_type

  if (
    !source ||
    typeof source.id !== 'string' ||
    typeof source.title !== 'string' ||
    typeof source.starts_at !== 'string' ||
    (eventType !== 'party' && eventType !== 'open_class')
  ) {
    return null
  }

  return {
    id: source.id,
    event_type: eventType,
    title: source.title,
    description: nullableString(source.description),
    starts_at: source.starts_at,
    ends_at: nullableString(source.ends_at),
    venue: venue(source.venue),
    style: style(source.style),
    attending: source.attending === true,
  }
}

function parseClass(value: unknown): GroupClass | null {
  const source = object(value)
  const danceStyle = style(source?.style)

  if (
    !source ||
    typeof source.id !== 'string' ||
    typeof source.starts_at !== 'string' ||
    typeof source.ends_at !== 'string' ||
    typeof source.group_id !== 'string' ||
    typeof source.group_title !== 'string' ||
    !danceStyle
  ) {
    return null
  }

  const visibility =
    source.visibility === 'members' || source.visibility === 'hidden'
      ? source.visibility
      : 'public'

  const bookingStatus =
    source.booking_status === 'booked' || source.booking_status === 'waitlisted'
      ? source.booking_status
      : null

  return {
    id: source.id,
    starts_at: source.starts_at,
    ends_at: source.ends_at,
    visibility,
    group_id: source.group_id,
    group_title: source.group_title,
    group_level: nullableString(source.group_level),
    style: danceStyle,
    venue: venue(source.venue),
    booking_status: bookingStatus,
    booking_id: typeof source.booking_id === 'string' ? source.booking_id : null,
    booking_role_id:
      typeof source.booking_role_id === 'number'
        ? source.booking_role_id
        : null,
    role_balance: (() => {
      const balance = object(source.role_balance)
      if (!balance) return null

      const leader =
        typeof balance.leader === 'number'
          ? balance.leader
          : Number(balance.leader)
      const follower =
        typeof balance.follower === 'number'
          ? balance.follower
          : Number(balance.follower)

      if (!Number.isFinite(leader) || !Number.isFinite(follower)) {
        return null
      }

      return { leader, follower }
    })(),
  }
}

function parseAttention(value: unknown): AttentionItem | null {
  const source = object(value)

  if (
    !source ||
    typeof source.id !== 'string' ||
    typeof source.title !== 'string'
  ) {
    return null
  }

  return {
    id: source.id,
    title: source.title,
    body: nullableString(source.body),
    priority: typeof source.priority === 'number' ? source.priority : 0,
    event: parseEvent(source.event),
  }
}

function parseList<T>(
  value: unknown,
  parser: (item: unknown) => T | null,
): T[] {
  return Array.isArray(value)
    ? value.map(parser).filter((item): item is T => item !== null)
    : []
}

export async function loadDancerHomeFeed(): Promise<DancerHomeFeed> {
  const [feedResult, attendState] = await Promise.all([
    supabase.rpc('get_my_dancer_home_feed', {
      p_event_limit: 20,
      p_class_limit: 20,
    }),
    loadQuickAttendState(),
  ])

  if (feedResult.error) throw feedResult.error

  const source = object(feedResult.data)
  if (!source) throw new Error('Dancer home feed is unavailable')

  const eventIds = new Set(attendState.eventIds)
  const bookings = new Map(
    attendState.bookings.map((booking) => [booking.slot_id, booking]),
  )

  const attachEventState = (event: DanceEvent): DanceEvent => ({
    ...event,
    attending: eventIds.has(event.id),
  })

  const attachClassState = (item: GroupClass): GroupClass => {
    const booking = bookings.get(item.id)

    return {
      ...item,
      booking_id: booking?.id ?? null,
      booking_status: booking?.status ?? null,
      booking_role_id: booking?.dance_role_id ?? null,
    }
  }

  return {
    attention: parseList(source.attention, parseAttention).map((item) => ({
      ...item,
      event: item.event ? attachEventState(item.event) : null,
    })),
    today_events: parseList(source.today_events, parseEvent).map(attachEventState),
    today_classes: parseList(source.today_classes, parseClass).map(attachClassState),
    events: parseList(source.events, parseEvent).map(attachEventState),
    classes: parseList(source.classes, parseClass).map(attachClassState),
  }
}
