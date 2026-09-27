import { supabase } from './supabase'

export type QuickAttendBooking = {
  id: string
  slot_id: string
  status: 'booked' | 'waitlisted'
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
      .select('id, slot_id, status')
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
          }
        })
        .filter((value): value is QuickAttendBooking => value !== null)
    : []

  return { eventIds, bookings }
}

export async function setEventAttending(
  eventId: string,
  attending: boolean,
): Promise<boolean> {
  const { data, error } = await supabase.rpc('set_my_event_attending', {
    p_event_id: eventId,
    p_attending: attending,
  })

  if (error) throw error
  return data === true
}

export async function setClassAttending({
  slotId,
  bookingId,
  attending,
}: {
  slotId: string
  bookingId: string | null
  attending: boolean
}): Promise<{
  attending: boolean
  bookingId: string | null
  status: 'booked' | 'waitlisted' | null
}> {
  if (attending) {
    const { data, error } = await supabase.rpc('book_class_slot', {
      p_slot_id: slotId,
      p_dance_role_id: null,
    })

    if (error) throw error

    const rawRow = Array.isArray(data) ? data[0] : data
    const row = rawRow as {
      id?: unknown
      status?: unknown
    } | null

    const status = bookingStatus(row?.status)
    if (!row || typeof row.id !== 'string' || !status) {
      throw new Error('Booking response is invalid')
    }

    return {
      attending: true,
      bookingId: row.id,
      status,
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
  }
}
