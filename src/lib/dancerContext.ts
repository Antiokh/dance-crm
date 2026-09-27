import { supabase } from './supabase'

export type AppRole = 'dancer' | 'trainer' | 'administrator'

export type DancerSummary = {
  id: string
  telegram_id: number | null
  telegram_username: string | null
  first_name: string | null
  last_name: string | null
  custom_name: string | null
  lang_code: string
  premium: boolean
  primary_role: number | null
}

export type DanceStyle = {
  id: number
  title_en: string | null
  title_ru: string | null
  title_sr: string | null
  is_partner_dance: boolean
  main_role: number | null
  role_ids: number[]
}

export type DancerContext = {
  dancer: DancerSummary
  roles: AppRole[]
  styles: DanceStyle[]
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function nullableString(value: unknown) {
  return typeof value === 'string' ? value : null
}

function parseRole(value: unknown): AppRole | null {
  return value === 'dancer' ||
    value === 'trainer' ||
    value === 'administrator'
    ? value
    : null
}

function parseStyle(value: unknown): DanceStyle | null {
  const source = record(value)
  if (!source || typeof source.id !== 'number') return null

  return {
    id: source.id,
    title_en: nullableString(source.title_en),
    title_ru: nullableString(source.title_ru),
    title_sr: nullableString(source.title_sr),
    is_partner_dance: source.is_partner_dance !== false,
    main_role:
      typeof source.main_role === 'number' ? source.main_role : null,
    role_ids: Array.isArray(source.role_ids)
      ? source.role_ids.filter((role): role is number => typeof role === 'number')
      : [],
  }
}

export function parseDancerContext(value: unknown): DancerContext {
  const source = record(value)
  const dancer = record(source?.dancer)

  if (!dancer || typeof dancer.id !== 'string') {
    throw new Error('Dancer profile is missing from context')
  }

  const roles = Array.isArray(source?.roles)
    ? source.roles
        .map(parseRole)
        .filter((role): role is AppRole => role !== null)
    : []

  if (!roles.includes('dancer')) {
    throw new Error('Dancer role is missing from authenticated context')
  }

  return {
    dancer: {
      id: dancer.id,
      telegram_id:
        typeof dancer.telegram_id === 'number'
          ? dancer.telegram_id
          : null,
      telegram_username: nullableString(dancer.telegram_username),
      first_name: nullableString(dancer.first_name),
      last_name: nullableString(dancer.last_name),
      custom_name: nullableString(dancer.custom_name),
      lang_code:
        typeof dancer.lang_code === 'string' ? dancer.lang_code : 'en',
      premium: dancer.premium === true,
      primary_role:
        typeof dancer.primary_role === 'number'
          ? dancer.primary_role
          : null,
    },
    roles,
    styles: Array.isArray(source?.styles)
      ? source.styles
          .map(parseStyle)
          .filter((style): style is DanceStyle => style !== null)
      : [],
  }
}

export async function loadMyDancerContext() {
  const { data, error } = await supabase.rpc('get_my_dancer_context')
  if (error) throw error
  if (data === null) throw new Error('Dancer context is empty')
  return parseDancerContext(data)
}
