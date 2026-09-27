import { supabase } from './supabase'
import type { AppRole } from './dancerContext'

export type AdminCompetitionProfile = {
  id: string | null
  system_code: string
  level_id: number
  points: number | null
  external_profile_id: string | null
  last_synced_at: string | null
}

export type AdminDancerStyleProfile = {
  id: string | null
  style_id: number
  is_leader: boolean
  is_trainer: boolean
  is_default: boolean
  training_level_id: number | null
  competition_profiles: AdminCompetitionProfile[]
}

export type AdminDancer = {
  id: string
  telegram_id: number | null
  telegram_username: string | null
  first_name: string | null
  last_name: string | null
  custom_name: string | null
  lang_code: string
  primary_role: number | null
  auth_linked: boolean
  roles: AppRole[]
  profiles: AdminDancerStyleProfile[]
}

export type AdminGroup = {
  id: string
  style_id: number
  title: string
  description: string | null
  level_id: number | null
  max_capacity: number | null
  approval_required: boolean
  enrollment_status: 'open' | 'closed' | 'waitlist_only' | 'archived'
  starts_on: string | null
  ends_on: string | null
  active: boolean
  lead_trainer_id: string | null
}

export type AdminEvent = {
  id: string
  event_type: 'party' | 'open_class'
  title: string
  description: string | null
  starts_at: string
  ends_at: string | null
  venue_id: string | null
  style_id: number | null
  published: boolean
  cancelled_at: string | null
}

export type AdminVenue = {
  id: string
  name: string
  address: string | null
  latitude: number | null
  longitude: number | null
  capacity: number | null
  notes: string | null
  active: boolean
}

export type AdminStyle = {
  id: number
  title_en: string | null
  title_ru: string | null
  title_sr: string | null
  is_partner_dance: boolean
}

export type AdminLevel = {
  id: number
  style_id: number
  code: string
  title_en: string
  title_ru: string | null
  title_sr: string | null
  rank_order: number
  active: boolean
  kind: 'training' | 'competition'
  system_code: string
  is_sport_achievement: boolean
  description: string | null
}

export type AdminCatalog = {
  dancers: AdminDancer[]
  groups: AdminGroup[]
  events: AdminEvent[]
  venues: AdminVenue[]
  styles: AdminStyle[]
  levels: AdminLevel[]
}

type JsonRecord = Record<string, unknown>

function asRecord(value: unknown): JsonRecord | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as JsonRecord
    : null
}

function stringOrNull(value: unknown) {
  return typeof value === 'string' ? value : null
}

function numberOrNull(value: unknown) {
  return typeof value === 'number' ? value : null
}

function parseCompetition(value: unknown): AdminCompetitionProfile | null {
  const row = asRecord(value)
  if (
    !row
    || typeof row.system_code !== 'string'
    || typeof row.level_id !== 'number'
  ) {
    return null
  }

  return {
    id: stringOrNull(row.id),
    system_code: row.system_code,
    level_id: row.level_id,
    points: numberOrNull(row.points),
    external_profile_id: stringOrNull(row.external_profile_id),
    last_synced_at: stringOrNull(row.last_synced_at),
  }
}

function parseDancerProfile(value: unknown): AdminDancerStyleProfile | null {
  const row = asRecord(value)
  if (!row || typeof row.style_id !== 'number') return null

  return {
    id: stringOrNull(row.id),
    style_id: row.style_id,
    is_leader: row.is_leader === true,
    is_trainer: row.is_trainer === true,
    is_default: row.is_default === true,
    training_level_id: numberOrNull(row.training_level_id),
    competition_profiles: Array.isArray(row.competition_profiles)
      ? row.competition_profiles
          .map(parseCompetition)
          .filter((item): item is AdminCompetitionProfile => item !== null)
      : [],
  }
}

function parseDancer(value: unknown): AdminDancer | null {
  const row = asRecord(value)
  if (!row || typeof row.id !== 'string') return null

  const roles = Array.isArray(row.roles)
    ? row.roles.filter(
        (role): role is AppRole =>
          role === 'dancer'
          || role === 'trainer'
          || role === 'administrator',
      )
    : []

  return {
    id: row.id,
    telegram_id: numberOrNull(row.telegram_id),
    telegram_username: stringOrNull(row.telegram_username),
    first_name: stringOrNull(row.first_name),
    last_name: stringOrNull(row.last_name),
    custom_name: stringOrNull(row.custom_name),
    lang_code: typeof row.lang_code === 'string' ? row.lang_code : 'ru',
    primary_role: numberOrNull(row.primary_role),
    auth_linked: row.auth_linked === true,
    roles,
    profiles: Array.isArray(row.profiles)
      ? row.profiles
          .map(parseDancerProfile)
          .filter((item): item is AdminDancerStyleProfile => item !== null)
      : [],
  }
}

function activeTrainerLink(row: {
  starts_on: string | null
  ends_on: string | null
}) {
  const today = new Date().toISOString().slice(0, 10)
  return (!row.starts_on || row.starts_on <= today)
    && (!row.ends_on || row.ends_on >= today)
}

export async function loadAdminCatalog(): Promise<AdminCatalog> {
  const [
    dancersResult,
    groupsResult,
    trainerLinksResult,
    eventsResult,
    venuesResult,
    stylesResult,
    levelsResult,
  ] = await Promise.all([
    supabase.rpc('get_admin_dancers'),
    supabase
      .from('dance_group')
      .select('id, style_id, title, description, level_id, max_capacity, approval_required, enrollment_status, starts_on, ends_on, active')
      .order('active', { ascending: false })
      .order('title'),
    supabase
      .from('group_trainers')
      .select('group_id, trainer_id, trainer_role, starts_on, ends_on, created_at'),
    supabase
      .from('dance_events')
      .select('id, event_type, title, description, starts_at, ends_at, venue_id, style_id, published, cancelled_at')
      .order('starts_at'),
    supabase
      .from('venues')
      .select('id, name, address, latitude, longitude, capacity, notes, active')
      .order('active', { ascending: false })
      .order('name'),
    supabase
      .from('l_dance_style')
      .select('id, title_en, title_ru, title_sr, is_partner_dance')
      .order('title_en'),
    supabase
      .from('styles_levels')
      .select('id, style_id, code, title_en, title_ru, title_sr, rank_order, active, kind, system_code, is_sport_achievement, description')
      .order('style_id')
      .order('kind')
      .order('system_code')
      .order('rank_order'),
  ])

  for (const result of [
    dancersResult,
    groupsResult,
    trainerLinksResult,
    eventsResult,
    venuesResult,
    stylesResult,
    levelsResult,
  ]) {
    if (result.error) throw result.error
  }

  const dancers = Array.isArray(dancersResult.data)
    ? dancersResult.data
        .map(parseDancer)
        .filter((item): item is AdminDancer => item !== null)
    : []

  const trainerLinks = (trainerLinksResult.data ?? []).map((row) => ({
    group_id: String(row.group_id),
    trainer_id: String(row.trainer_id),
    trainer_role: String(row.trainer_role),
    starts_on: typeof row.starts_on === 'string' ? row.starts_on : null,
    ends_on: typeof row.ends_on === 'string' ? row.ends_on : null,
    created_at: typeof row.created_at === 'string' ? row.created_at : '',
  }))

  const groups: AdminGroup[] = (groupsResult.data ?? []).map((row) => {
    const leadLinks = trainerLinks
      .filter(
        (link) =>
          link.group_id === String(row.id)
          && link.trainer_role === 'lead',
      )
      .sort((a, b) => {
        const activeDiff =
          Number(activeTrainerLink(b)) - Number(activeTrainerLink(a))
        if (activeDiff !== 0) return activeDiff
        return b.created_at.localeCompare(a.created_at)
      })

    return {
      id: String(row.id),
      style_id: Number(row.style_id),
      title: String(row.title),
      description: stringOrNull(row.description),
      level_id: numberOrNull(row.level_id),
      max_capacity: numberOrNull(row.max_capacity),
      approval_required: row.approval_required === true,
      enrollment_status:
        row.enrollment_status === 'closed'
        || row.enrollment_status === 'waitlist_only'
        || row.enrollment_status === 'archived'
          ? row.enrollment_status
          : 'open',
      starts_on: stringOrNull(row.starts_on),
      ends_on: stringOrNull(row.ends_on),
      active: row.active === true,
      lead_trainer_id: leadLinks[0]?.trainer_id ?? null,
    }
  })

  const events: AdminEvent[] = (eventsResult.data ?? []).map((row) => ({
    id: String(row.id),
    event_type: row.event_type === 'open_class' ? 'open_class' : 'party',
    title: String(row.title),
    description: stringOrNull(row.description),
    starts_at: String(row.starts_at),
    ends_at: stringOrNull(row.ends_at),
    venue_id: stringOrNull(row.venue_id),
    style_id: numberOrNull(row.style_id),
    published: row.published === true,
    cancelled_at: stringOrNull(row.cancelled_at),
  }))

  const venues: AdminVenue[] = (venuesResult.data ?? []).map((row) => ({
    id: String(row.id),
    name: String(row.name),
    address: stringOrNull(row.address),
    latitude: numberOrNull(row.latitude),
    longitude: numberOrNull(row.longitude),
    capacity: numberOrNull(row.capacity),
    notes: stringOrNull(row.notes),
    active: row.active === true,
  }))

  const styles: AdminStyle[] = (stylesResult.data ?? []).map((row) => ({
    id: Number(row.id),
    title_en: stringOrNull(row.title_en),
    title_ru: stringOrNull(row.title_ru),
    title_sr: stringOrNull(row.title_sr),
    is_partner_dance: row.is_partner_dance !== false,
  }))

  const levels: AdminLevel[] = (levelsResult.data ?? []).map((row) => ({
    id: Number(row.id),
    style_id: Number(row.style_id),
    code: String(row.code),
    title_en: String(row.title_en),
    title_ru: stringOrNull(row.title_ru),
    title_sr: stringOrNull(row.title_sr),
    rank_order:
      typeof row.rank_order === 'number'
        ? row.rank_order
        : 0,
    active: row.active === true,
    kind: row.kind === 'competition' ? 'competition' : 'training',
    system_code:
      typeof row.system_code === 'string'
        ? row.system_code
        : 'school',
    is_sport_achievement: row.is_sport_achievement === true,
    description: stringOrNull(row.description),
  }))

  return { dancers, groups, events, venues, styles, levels }
}

export type AdminDancerPayload = {
  telegram_id: number | null
  telegram_username: string | null
  first_name: string | null
  last_name: string | null
  custom_name: string | null
  lang_code: string
  primary_role: number | null
  is_administrator: boolean
  profiles: Array<{
    style_id: number
    is_leader: boolean
    is_trainer: boolean
    is_default: boolean
    training_level_id: number | null
    competition_profiles: Array<{
      system_code: string
      level_id: number
      points: number | null
      external_profile_id: string | null
      last_synced_at: string | null
    }>
  }>
}

export async function saveAdminDancer(
  dancerId: string | null,
  payload: AdminDancerPayload,
) {
  const { data, error } = await supabase.rpc('admin_save_dancer', {
    p_dancer_id: dancerId,
    p_payload: payload,
  })
  if (error) throw error
  if (typeof data !== 'string') throw new Error('Dancer save response is invalid')
  return data
}

export type AdminGroupInput = Omit<AdminGroup, 'id' | 'title'> & {
  id: string | null
}

export async function saveAdminGroup(input: AdminGroupInput) {
  const values = {
    style_id: input.style_id,
    description: input.description,
    level_id: input.level_id,
    max_capacity: input.max_capacity,
    approval_required: input.approval_required,
    enrollment_status: input.enrollment_status,
    starts_on: input.starts_on,
    ends_on: input.ends_on,
    active: input.active,
  }

  let groupId = input.id

  if (groupId) {
    const { error } = await supabase
      .from('dance_group')
      .update(values)
      .eq('id', groupId)
    if (error) throw error
  } else {
    const { data, error } = await supabase
      .from('dance_group')
      .insert(values)
      .select('id')
      .single()
    if (error) throw error
    groupId = String(data.id)
  }

  const { error: deleteError } = await supabase
    .from('group_trainers')
    .delete()
    .eq('group_id', groupId)
    .eq('trainer_role', 'lead')
  if (deleteError) throw deleteError

  if (input.lead_trainer_id) {
    const { error: trainerError } = await supabase
      .from('group_trainers')
      .insert({
        group_id: groupId,
        trainer_id: input.lead_trainer_id,
        trainer_role: 'lead',
        starts_on: input.starts_on,
        ends_on: input.ends_on,
      })
    if (trainerError) throw trainerError
  }

  return groupId
}

export type AdminEventInput = Omit<
  AdminEvent,
  'id' | 'starts_at' | 'ends_at' | 'cancelled_at'
> & {
  id: string | null
  starts_local: string
  ends_local: string
  cancelled: boolean
  existing_cancelled_at: string | null
}

export function isoToLocalInput(value: string | null) {
  if (!value) return ''
  const date = new Date(value)
  const parts = new Intl.DateTimeFormat('sv-SE', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'Europe/Belgrade',
  }).formatToParts(date)
  const map = new Map(parts.map((part) => [part.type, part.value]))
  return `${map.get('year')}-${map.get('month')}-${map.get('day')}T${map.get('hour')}:${map.get('minute')}`
}

function localInputToIso(value: string) {
  if (!value) return null
  // Admin UI is explicitly Europe/Belgrade. Browsers running in that timezone
  // parse datetime-local correctly; this fallback keeps the input contract simple.
  return new Date(value).toISOString()
}

export async function saveAdminEvent(input: AdminEventInput) {
  const values = {
    event_type: input.event_type,
    title: input.title.trim(),
    description: input.description?.trim() || null,
    starts_at: localInputToIso(input.starts_local),
    ends_at: localInputToIso(input.ends_local),
    venue_id: input.venue_id,
    style_id: input.style_id,
    published: input.published,
    cancelled_at: input.cancelled
      ? input.existing_cancelled_at ?? new Date().toISOString()
      : null,
  }

  if (!values.starts_at) throw new Error('Укажите дату и время события')

  if (input.id) {
    const { error } = await supabase
      .from('dance_events')
      .update(values)
      .eq('id', input.id)
    if (error) throw error
    return input.id
  }

  const { data, error } = await supabase
    .from('dance_events')
    .insert(values)
    .select('id')
    .single()
  if (error) throw error
  return String(data.id)
}

export type AdminVenueInput = Omit<AdminVenue, 'id'> & {
  id: string | null
}

export async function saveAdminVenue(input: AdminVenueInput) {
  const values = {
    name: input.name.trim(),
    address: input.address?.trim() || null,
    latitude: input.latitude,
    longitude: input.longitude,
    capacity: input.capacity,
    notes: input.notes?.trim() || null,
    active: input.active,
  }

  if (input.id) {
    const { error } = await supabase
      .from('venues')
      .update(values)
      .eq('id', input.id)
    if (error) throw error
    return input.id
  }

  const { data, error } = await supabase
    .from('venues')
    .insert(values)
    .select('id')
    .single()
  if (error) throw error
  return String(data.id)
}

export async function saveAdminStyle(
  styleId: number | null,
  payload: Omit<AdminStyle, 'id'>,
) {
  const { data, error } = await supabase.rpc('admin_save_style', {
    p_style_id: styleId,
    p_payload: payload,
  })
  if (error) throw error
  if (typeof data !== 'number') throw new Error('Style save response is invalid')
  return data
}

export async function saveAdminLevel(
  levelId: number | null,
  payload: Omit<AdminLevel, 'id'>,
) {
  const { data, error } = await supabase.rpc('admin_save_level', {
    p_level_id: levelId,
    p_payload: payload,
  })
  if (error) throw error
  if (typeof data !== 'number') throw new Error('Level save response is invalid')
  return data
}
