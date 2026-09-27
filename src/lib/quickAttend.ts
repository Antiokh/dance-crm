import { supabase } from './supabase'

export type QuickAttendBooking = {
  id: string
  slot_id: string
  status: 'booked' | 'waitlisted'
  dance_role_id: number | null
}

export type QuickAttendState = {
  eventIds: string[]
  bookings: QuickAttendBooking[]
}

function bookingStatus(value: unknown): QuickAttendBooking['status'] | null {
  return value === 'booked' || value === 'waitlisted' ? value : null
}

export async function loadQuickAttendState(): Promise<QuickAttendState> {
  const [eventsResult, bookingsResult] = await Promise.all([
    supabase.rpc('get_my_event_attendance'),
    supabase
      .from('bookings')
      .select('id, slot_id, status, dance_role_id')
      .neq('status', 'cancelled'),
  ])

  if (eventsResult.error) throw eventsResult.error
  if (bookingsResult.error) throw bookingsResult.error

  const eventIds = Array.isArray(eventsResult.data)
    ? eventsResult.data
        .map((row) => (
          typeof row === 'object' &&
          row !== null &&
          typeof (row as { event_id?: unknown }).event_id === 'string'
            ? (row as { event_id: string }).event_id
            : null
        ))
        .filter((value): value is string => value !== null)
    : []

  const bookings = Array.isArray(bookingsResult.data)
    ? bookingsResult.data
        .map((row) => {
          if (
            !row ||
            typeof row.id !== 'string' ||
            typeof row.slot_id !== 'string'
          ) {
            return null
          }

          const status = bookingStatus(row.status)
          if (!status) return null

          return {
            id: row.id,
            slot_id: row.slot_id,
            status,
            dance_role_id:
              typeof row.dance_role_id === 'number'
                ? row.dance_role_id
                : null,
          }
        })
        .filter((value): value is QuickAttendBooking => value !== null)
    : []

  return { eventIds, bookings }
}

export type QuickAttendEventResult = {
  attending: boolean
  roleBalance: {
    leader: number
    follower: number
    other: number
  }
}

export async function setEventAttending(
  eventId: string,
  attending: boolean,
): Promise<QuickAttendEventResult> {
  const { data, error } = await supabase.rpc('set_my_event_attending', {
    p_event_id: eventId,
    p_attending: attending,
  })

  if (error) throw error

  const { data: rsvpData, error: rsvpError } = await supabase.rpc(
    'get_my_event_rsvp',
    { p_event_id: eventId },
  )
  if (rsvpError) throw rsvpError

  const row =
    rsvpData && typeof rsvpData === 'object' && !Array.isArray(rsvpData)
      ? rsvpData as Record<string, unknown>
      : {}

  return {
    attending: data === true,
    roleBalance: {
      leader:
        typeof row.leader_going_count === 'number'
          ? row.leader_going_count
          : 0,
      follower:
        typeof row.follower_going_count === 'number'
          ? row.follower_going_count
          : 0,
      other:
        typeof row.other_going_count === 'number'
          ? row.other_going_count
          : 0,
    },
  }
}

export async function setClassAttending({
  slotId,
  bookingId,
  roleId,
  attending,
}: {
  slotId: string
  bookingId: string | null
  roleId: number | null
  attending: boolean
}): Promise<{
  attending: boolean
  bookingId: string | null
  status: 'booked' | 'waitlisted' | null
  roleId: number | null
}> {
  if (attending) {
    const { data, error } = await supabase.rpc('book_class_slot', {
      p_slot_id: slotId,
      p_dance_role_id: roleId,
    })

    if (error) throw error

    const rawRow = Array.isArray(data) ? data[0] : data
    const row = rawRow as {
      id?: unknown
      status?: unknown
      dance_role_id?: unknown
    } | null

    const status = bookingStatus(row?.status)
    if (!row || typeof row.id !== 'string' || !status) {
      throw new Error('Booking response is invalid')
    }

    return {
      attending: true,
      bookingId: row.id,
      status,
      roleId:
        typeof row.dance_role_id === 'number'
          ? row.dance_role_id
          : roleId,
    }
  }

  let targetBookingId = bookingId

  if (!targetBookingId) {
    const { data, error } = await supabase
      .from('bookings')
      .select('id')
      .eq('slot_id', slotId)
      .neq('status', 'cancelled')
      .maybeSingle()

    if (error) throw error
    targetBookingId =
      data && typeof data.id === 'string'
        ? data.id
        : null
  }

  if (!targetBookingId) {
    return {
      attending: false,
      bookingId: null,
      status: null,
      roleId,
    }
  }

  const { error } = await supabase.rpc('cancel_my_booking', {
    p_booking_id: targetBookingId,
  })

  if (error) throw error

  return {
    attending: false,
    bookingId: targetBookingId,
    status: null,
    roleId,
  }
}

export async function changeClassBookingRole(
  bookingId: string,
  roleId: number,
): Promise<number> {
  const { data, error } = await supabase.rpc('change_my_booking_role', {
    p_booking_id: bookingId,
    p_dance_role_id: roleId,
  })

  if (error) throw error

  const rawRow = Array.isArray(data) ? data[0] : data
  const row = rawRow as {
    dance_role_id?: unknown
  } | null

  if (!row || typeof row.dance_role_id !== 'number') {
    throw new Error('Booking role response is invalid')
  }

  return row.dance_role_id
}
