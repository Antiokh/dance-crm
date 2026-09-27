import { supabase } from './supabase'

export type ProfileSubscription = {
  id: string
  planName: string
  startsAt: string
  endsAt: string | null
  effectiveStatus: string
  remainingClasses: number | null
  remainingSkips: number | null
}

export type AttendedClass = {
  id: string
  startsAt: string
  endsAt: string
  groupTitle: string
  styleTitle: string
  venueName: string | null
}

export type DancerProfileData = {
  subscriptions: ProfileSubscription[]
  attendedClasses: AttendedClass[]
  attendedEvents: []
}

function styleTitle(row: {
  title_ru?: string | null
  title_en?: string | null
  title_sr?: string | null
}) {
  return row.title_ru?.trim()
    || row.title_en?.trim()
    || row.title_sr?.trim()
    || 'Стиль'
}

export async function loadDancerProfileData(): Promise<DancerProfileData> {
  const [subscriptionsResult, bookingsResult] = await Promise.all([
    supabase
      .from('v_my_subscriptions')
      .select(
        'id, plan_name, starts_at, ends_at, effective_status, remaining_classes, remaining_skips',
      )
      .order('starts_at', { ascending: false }),
    supabase
      .from('bookings')
      .select('id, slot_id, attendance_status')
      .eq('attendance_status', 'attended'),
  ])

  if (subscriptionsResult.error) throw subscriptionsResult.error
  if (bookingsResult.error) throw bookingsResult.error

  const subscriptions: ProfileSubscription[] = (subscriptionsResult.data ?? []).map((row) => ({
    id: String(row.id),
    planName: String(row.plan_name),
    startsAt: String(row.starts_at),
    endsAt: typeof row.ends_at === 'string' ? row.ends_at : null,
    effectiveStatus:
      typeof row.effective_status === 'string'
        ? row.effective_status
        : 'unknown',
    remainingClasses:
      typeof row.remaining_classes === 'number'
        ? row.remaining_classes
        : null,
    remainingSkips:
      typeof row.remaining_skips === 'number'
        ? row.remaining_skips
        : null,
  }))

  const slotIds = Array.from(
    new Set(
      (bookingsResult.data ?? [])
        .map((row) => String(row.slot_id))
        .filter(Boolean),
    ),
  )

  if (slotIds.length === 0) {
    return {
      subscriptions,
      attendedClasses: [],
      attendedEvents: [],
    }
  }

  const slotsResult = await supabase
    .from('class_slots')
    .select('id, group_id, venue_id, starts_at, ends_at')
    .in('id', slotIds)

  if (slotsResult.error) throw slotsResult.error

  const slotRows = slotsResult.data ?? []
  const groupIds = Array.from(
    new Set(slotRows.map((row) => String(row.group_id)).filter(Boolean)),
  )
  const venueIds = Array.from(
    new Set(
      slotRows
        .map((row) => (
          typeof row.venue_id === 'string' ? row.venue_id : null
        ))
        .filter((value): value is string => value !== null),
    ),
  )

  const [groupsResult, venuesResult] = await Promise.all([
    groupIds.length > 0
      ? supabase
          .from('dance_group')
          .select('id, title, style_id')
          .in('id', groupIds)
      : Promise.resolve({ data: [], error: null }),
    venueIds.length > 0
      ? supabase
          .from('venues')
          .select('id, name')
          .in('id', venueIds)
      : Promise.resolve({ data: [], error: null }),
  ])

  if (groupsResult.error) throw groupsResult.error
  if (venuesResult.error) throw venuesResult.error

  const groupRows = groupsResult.data ?? []
  const styleIds = Array.from(
    new Set(groupRows.map((row) => Number(row.style_id))),
  )

  const stylesResult = styleIds.length > 0
    ? await supabase
        .from('l_dance_style')
        .select('id, title_en, title_ru, title_sr')
        .in('id', styleIds)
    : { data: [], error: null }

  if (stylesResult.error) throw stylesResult.error

  const styleMap = new Map(
    (stylesResult.data ?? []).map((row) => [Number(row.id), styleTitle(row)]),
  )
  const groupMap = new Map(
    groupRows.map((row) => [
      String(row.id),
      {
        title: String(row.title),
        styleTitle: styleMap.get(Number(row.style_id)) ?? 'Стиль',
      },
    ]),
  )
  const venueMap = new Map(
    (venuesResult.data ?? []).map((row) => [String(row.id), String(row.name)]),
  )

  const attendedClasses: AttendedClass[] = slotRows
    .map((slot) => {
      const group = groupMap.get(String(slot.group_id))
      if (!group) return null

      return {
        id: String(slot.id),
        startsAt: String(slot.starts_at),
        endsAt: String(slot.ends_at),
        groupTitle: group.title,
        styleTitle: group.styleTitle,
        venueName:
          typeof slot.venue_id === 'string'
            ? venueMap.get(slot.venue_id) ?? null
            : null,
      }
    })
    .filter((item): item is AttendedClass => item !== null)
    .sort(
      (a, b) =>
        new Date(b.startsAt).getTime() - new Date(a.startsAt).getTime(),
    )

  return {
    subscriptions,
    attendedClasses,
    attendedEvents: [],
  }
}
