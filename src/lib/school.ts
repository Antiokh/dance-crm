import { supabase } from './supabase'

export type SchoolGroup = {
  id: string
  title: string
  description: string | null
  levelId: number | null
  level: string | null
  maxCapacity: number | null
  enrollmentStatus: string
  styleTitle: string
}

export type SchoolTrainer = {
  id: string
  name: string
  groups: string[]
}

export type SchoolVenue = {
  id: string
  name: string
  address: string | null
  capacity: number | null
}

export type SchoolStyleLevel = {
  id: number
  code: string
  title: string
  rankOrder: number
}

export type SchoolStyle = {
  id: number
  title: string
  isPartnerDance: boolean
  levels: SchoolStyleLevel[]
}

export type SchoolCatalog = {
  groups: SchoolGroup[]
  trainers: SchoolTrainer[]
  venues: SchoolVenue[]
  styles: SchoolStyle[]
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

function dancerName(row: {
  custom_name?: string | null
  first_name?: string | null
  last_name?: string | null
  telegram_username?: string | null
}) {
  if (row.custom_name?.trim()) return row.custom_name.trim()
  const fullName = [row.first_name, row.last_name]
    .filter(Boolean)
    .join(' ')
    .trim()
  if (fullName) return fullName
  if (row.telegram_username?.trim()) return `@${row.telegram_username.trim()}`
  return 'Тренер'
}

export async function loadSchoolCatalog(): Promise<SchoolCatalog> {
  const [
    groupsResult,
    trainerLinksResult,
    venuesResult,
    stylesResult,
    levelsResult,
  ] = await Promise.all([
    supabase
      .from('dance_group')
      .select('id, style_id, title, description, level_id, max_capacity, enrollment_status')
      .eq('active', true)
      .order('title'),
    supabase
      .from('group_trainers')
      .select('group_id, trainer_id, starts_on, ends_on'),
    supabase
      .from('venues')
      .select('id, name, address, capacity')
      .eq('active', true)
      .order('name'),
    supabase
      .from('l_dance_style')
      .select('id, title_en, title_ru, title_sr, is_partner_dance')
      .order('title_en'),
    supabase
      .from('styles_levels')
      .select('id, style_id, code, title_en, title_ru, title_sr, rank_order')
      .eq('active', true)
      .order('rank_order')
      .order('title_en'),
  ])

  if (groupsResult.error) throw groupsResult.error
  if (trainerLinksResult.error) throw trainerLinksResult.error
  if (venuesResult.error) throw venuesResult.error
  if (stylesResult.error) throw stylesResult.error
  if (levelsResult.error) throw levelsResult.error

  const levels = (levelsResult.data ?? []).map((row) => ({
    id: Number(row.id),
    styleId: Number(row.style_id),
    code: String(row.code),
    title: styleTitle(row),
    rankOrder:
      typeof row.rank_order === 'number'
        ? row.rank_order
        : 0,
  }))

  const styles = (stylesResult.data ?? []).map((row) => ({
    id: Number(row.id),
    title: styleTitle(row),
    isPartnerDance: row.is_partner_dance === true,
    levels: levels
      .filter((level) => level.styleId === Number(row.id))
      .map(({ styleId: _styleId, ...level }) => level),
  }))

  const styleMap = new Map(styles.map((style) => [style.id, style.title]))
  const levelMap = new Map(
    levels.map((level) => [level.id, level.title]),
  )
  const groupRows = groupsResult.data ?? []
  const groupMap = new Map(
    groupRows.map((group) => [String(group.id), String(group.title)]),
  )

  const groups: SchoolGroup[] = groupRows.map((row) => ({
    id: String(row.id),
    title: String(row.title),
    description: typeof row.description === 'string' ? row.description : null,
    levelId:
      typeof row.level_id === 'number'
        ? row.level_id
        : null,
    level:
      typeof row.level_id === 'number'
        ? levelMap.get(row.level_id) ?? null
        : null,
    maxCapacity: typeof row.max_capacity === 'number' ? row.max_capacity : null,
    enrollmentStatus:
      typeof row.enrollment_status === 'string'
        ? row.enrollment_status
        : 'closed',
    styleTitle: styleMap.get(Number(row.style_id)) ?? 'Стиль',
  }))

  const today = new Date().toISOString().slice(0, 10)
  const activeTrainerLinks = (trainerLinksResult.data ?? []).filter((row) => {
    const startsOn = typeof row.starts_on === 'string' ? row.starts_on : null
    const endsOn = typeof row.ends_on === 'string' ? row.ends_on : null
    return (!startsOn || startsOn <= today) && (!endsOn || endsOn >= today)
  })

  const trainerIds = Array.from(
    new Set(
      activeTrainerLinks
        .map((row) => String(row.trainer_id))
        .filter(Boolean),
    ),
  )

  let trainerRows: Array<{
    id: string
    custom_name: string | null
    first_name: string | null
    last_name: string | null
    telegram_username: string | null
  }> = []

  if (trainerIds.length > 0) {
    const trainersResult = await supabase
      .from('dancer')
      .select('id, custom_name, first_name, last_name, telegram_username')
      .in('id', trainerIds)

    if (trainersResult.error) throw trainersResult.error
    trainerRows = (trainersResult.data ?? []) as typeof trainerRows
  }

  const trainerNameMap = new Map(
    trainerRows.map((row) => [row.id, dancerName(row)]),
  )

  const trainerGroupMap = new Map<string, Set<string>>()
  for (const link of activeTrainerLinks) {
    const trainerId = String(link.trainer_id)
    const groupTitle = groupMap.get(String(link.group_id))
    if (!groupTitle) continue

    const groupSet = trainerGroupMap.get(trainerId) ?? new Set<string>()
    groupSet.add(groupTitle)
    trainerGroupMap.set(trainerId, groupSet)
  }

  const trainers: SchoolTrainer[] = trainerIds
    .map((id) => ({
      id,
      name: trainerNameMap.get(id) ?? 'Тренер',
      groups: Array.from(trainerGroupMap.get(id) ?? []).sort(),
    }))
    .sort((a, b) => a.name.localeCompare(b.name, 'ru'))

  const venues: SchoolVenue[] = (venuesResult.data ?? []).map((row) => ({
    id: String(row.id),
    name: String(row.name),
    address: typeof row.address === 'string' ? row.address : null,
    capacity: typeof row.capacity === 'number' ? row.capacity : null,
  }))

  return { groups, trainers, venues, styles }
}
