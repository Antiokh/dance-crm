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
  const { data, error } = await supabase.rpc('get_my_dancer_home_feed', {
    p_event_limit: 20,
    p_class_limit: 20,
  })

  if (error) throw error

  const source = object(data)
  if (!source) throw new Error('Dancer home feed is unavailable')

  return {
    attention: parseList(source.attention, parseAttention),
    today_events: parseList(source.today_events, parseEvent),
    today_classes: parseList(source.today_classes, parseClass),
    events: parseList(source.events, parseEvent),
    classes: parseList(source.classes, parseClass),
  }
}
