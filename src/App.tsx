import { useEffect, useMemo, useState } from 'react'
import {
  Cell,
  List,
  Placeholder,
  Section,
  Spinner,
  Tabbar,
  TabsList,
} from '@telegram-apps/telegram-ui'
import TelegramSwitch from './components/TelegramSwitch'
import {
  authenticateTelegram,
  type AuthState,
} from './lib/auth'
import type {
  AppRole,
  DanceStyle,
  DancerSummary,
} from './lib/dancerContext'
import {
  loadDancerHomeFeed,
  type DanceEvent,
  type DancerHomeFeed,
  type GroupClass,
  type HomeStyle,
} from './lib/homeFeed'
import {
  loadDancerProfileData,
  type DancerProfileData,
} from './lib/profile'
import {
  changeClassBookingRole,
  setClassAttending,
  setEventAttending,
} from './lib/quickAttend'
import {
  loadSchoolCatalog,
  type SchoolCatalog,
} from './lib/school'
import { getTelegramUser, setTelegramVerticalSwipesEnabled } from './lib/telegram'
import { getNativeTelegramUser } from './lib/tma'

const initialAuth: AuthState = {
  status: 'preview',
  session: null,
  context: null,
  error: null,
}

const roleLabels: Record<AppRole, string> = {
  dancer: 'Танцор',
  trainer: 'Тренер',
  administrator: 'Администратор',
}

type RootView = 'activities' | 'info' | 'profile'
type SchoolView = 'groups' | 'trainers' | 'venues' | 'styles'

type AsyncState<T> =
  | { status: 'idle' | 'loading'; data: T | null; error: null }
  | { status: 'ready'; data: T; error: null }
  | { status: 'error'; data: null; error: string }

type FeedState = AsyncState<DancerHomeFeed>
type SchoolState = AsyncState<SchoolCatalog>
type ProfileState = AsyncState<DancerProfileData>

type TodayItem =
  | { kind: 'event'; startsAt: string; event: DanceEvent }
  | { kind: 'class'; startsAt: string; item: GroupClass }

type ClassAttendState = {
  attending: boolean
  bookingId: string | null
  status: 'booked' | 'waitlisted' | null
  roleId: number | null
}

function displayName(dancer: DancerSummary) {
  if (dancer.custom_name?.trim()) return dancer.custom_name.trim()

  const fullName = [dancer.first_name, dancer.last_name]
    .filter(Boolean)
    .join(' ')
    .trim()

  return fullName || dancer.telegram_username || 'Dancer'
}

function initials(dancer: DancerSummary) {
  return displayName(dancer)
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('')
    .slice(0, 2)
}

function telegramDisplayName(user: ReturnType<typeof getTelegramUser>) {
  if (!user) return 'Dancers'
  const fullName = [user.first_name, user.last_name]
    .filter(Boolean)
    .join(' ')
    .trim()
  return fullName || (user.username ? `@${user.username}` : 'Dancers')
}

function telegramInitials(user: ReturnType<typeof getTelegramUser>) {
  if (!user) return 'D'
  const value = [user.first_name, user.last_name]
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part?.trim().charAt(0).toUpperCase() ?? '')
    .join('')
  return value || user.username?.slice(0, 2).toUpperCase() || 'D'
}

function styleTitle(style: HomeStyle | null) {
  if (!style) return null
  return (
    style.title_ru?.trim() ||
    style.title_en?.trim() ||
    style.title_sr?.trim() ||
    null
  )
}

function dateParts(value: string) {
  const date = new Date(value)

  return {
    day: new Intl.DateTimeFormat('ru-RU', {
      day: '2-digit',
      timeZone: 'Europe/Belgrade',
    }).format(date),
    weekday: new Intl.DateTimeFormat('ru-RU', {
      weekday: 'short',
      timeZone: 'Europe/Belgrade',
    }).format(date).replace('.', ''),
  }
}

function dateCaption(value: string) {
  return new Intl.DateTimeFormat('ru-RU', {
    day: 'numeric',
    month: 'short',
    timeZone: 'Europe/Belgrade',
  }).format(new Date(value)).replace('.', '')
}

function profileDate(value: string) {
  return new Intl.DateTimeFormat('ru-RU', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: 'Europe/Belgrade',
  }).format(new Date(value)).replace('.', '')
}

function shortTime(value: string) {
  return new Intl.DateTimeFormat('ru-RU', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Europe/Belgrade',
  }).format(new Date(value))
}

function timeRange(startsAt: string, endsAt: string | null) {
  const start = shortTime(startsAt)
  if (!endsAt) return start
  return `${start}–${shortTime(endsAt)}`
}

function eventTypeLabel(type: DanceEvent['event_type']) {
  return type === 'party' ? 'Вечеринка' : 'Опен'
}

function eventSubtitle(event: DanceEvent) {
  return [
    timeRange(event.starts_at, event.ends_at),
    event.venue?.name,
  ].filter(Boolean).join(' · ')
}

function eventDescription(event: DanceEvent) {
  return [
    styleTitle(event.style),
    event.description,
  ].filter(Boolean).join(' · ') || undefined
}

function classSubtitle(item: GroupClass) {
  return [
    styleTitle(item.style),
    timeRange(item.starts_at, item.ends_at),
  ].filter(Boolean).join(' · ')
}

function classDescription(
  item: GroupClass,
  status: 'booked' | 'waitlisted' | null = item.booking_status,
) {
  const prefix = [
    item.group_level,
    item.venue?.name,
  ].filter(Boolean).join(' · ')

  const statusText =
    status === 'waitlisted'
      ? 'Ожидает подтверждения'
      : status === 'booked' && !item.style.is_partner_dance
        ? 'Записан'
        : null

  return [prefix || null, statusText]
    .filter(Boolean)
    .join(' · ') || undefined
}

function RoleBalanceIndicator({
  balance,
}: {
  balance: GroupClass['role_balance']
}) {
  if (!balance) return null

  const total = balance.leader + balance.follower
  const leaderShare = total > 0
    ? Math.round((balance.leader / total) * 1000) / 10
    : 0

  const background = total > 0
    ? `conic-gradient(
        #5aa9ff 0 ${leaderShare}%,
        #f27ab1 ${leaderShare}% 100%
      )`
    : 'var(--tg-theme-secondary-bg-color, rgba(127, 127, 127, 0.24))'

  return (
    <span
      className="class-role-balance-pie"
      style={{ background }}
      role="img"
      aria-label={`Баланс: партнёры ${balance.leader}, партнёрши ${balance.follower}`}
    />
  )
}

function roleShortLabel(roleId: number | null) {
  if (roleId === 1) return 'Лид.'
  if (roleId === 2) return 'Фолл.'
  return roleId === null ? null : `Роль ${roleId}`
}

function QuickAttendToggle({
  checked,
  pending,
  danger = false,
  roleLabel,
  onRoleChange,
  onChange,
}: {
  checked: boolean
  pending: boolean
  danger?: boolean
  roleLabel?: string | null
  onRoleChange?: () => void
  onChange: (checked: boolean) => void
}) {
  return (
    <span
      className="quick-attend-control"
      onClick={(event) => event.stopPropagation()}
    >
      <TelegramSwitch
        className={danger ? 'quick-attend-switch-danger' : undefined}
        checked={checked}
        disabled={pending}
        onChange={(event) => onChange(event.target.checked)}
        aria-label={checked ? 'Я иду' : 'Отметиться: я иду'}
      />
      <span className="quick-attend-label">Я иду</span>
      {roleLabel && onRoleChange ? (
        <button
          type="button"
          className="quick-attend-role"
          disabled={pending}
          onClick={(event) => {
            event.stopPropagation()
            onRoleChange()
          }}
        >
          {roleLabel}
        </button>
      ) : null}
    </span>
  )
}

function DateBadge({
  value,
  balance = null,
}: {
  value: string
  balance?: GroupClass['role_balance']
}) {
  const parts = dateParts(value)

  return (
    <span className="tgui-trip-date">
      <strong>{parts.day}</strong>
      <span>{parts.weekday}</span>
      <RoleBalanceIndicator balance={balance} />
    </span>
  )
}

function TimeBadge({
  value,
  balance = null,
}: {
  value: string
  balance?: GroupClass['role_balance']
}) {
  return (
    <span className="dancer-home-time">
      <span>{shortTime(value)}</span>
      <RoleBalanceIndicator balance={balance} />
    </span>
  )
}

function LoadingBlock({ text }: { text: string }) {
  return (
    <Placeholder header={text}>
      <Spinner size="m" />
    </Placeholder>
  )
}

function DancerHome({
  state,
  dancerStyles,
}: {
  state: FeedState
  dancerStyles: DanceStyle[]
}) {
  const [eventsExpanded, setEventsExpanded] = useState(false)
  const [eventOverrides, setEventOverrides] = useState<Record<string, boolean>>({})
  const [classOverrides, setClassOverrides] = useState<Record<string, ClassAttendState>>({})
  const [pendingActions, setPendingActions] = useState<Record<string, boolean>>({})
  const [actionError, setActionError] = useState<string | null>(null)

  if (state.status === 'idle' || state.status === 'loading') {
    return <LoadingBlock text="Загружаю события" />
  }

  if (state.status === 'error') {
    return (
      <Placeholder
        header="Не удалось загрузить"
        description={state.error}
      />
    )
  }

  const todayItems: TodayItem[] = [
    ...state.data.today_events.map((event) => ({
      kind: 'event' as const,
      startsAt: event.starts_at,
      event,
    })),
    ...state.data.today_classes.map((item) => ({
      kind: 'class' as const,
      startsAt: item.starts_at,
      item,
    })),
  ].sort((a, b) => (
    new Date(a.startsAt).getTime() - new Date(b.startsAt).getTime()
  ))

  const visibleEvents = eventsExpanded
    ? state.data.events
    : state.data.events.slice(0, 2)
  const hiddenEventCount = Math.max(0, state.data.events.length - 2)

  const eventAttending = (event: DanceEvent) =>
    eventOverrides[event.id] ?? event.attending

  const styleProfile = (item: GroupClass) =>
    dancerStyles.find((style) => style.id === item.style.id) ?? null

  const availableRoleIds = (item: GroupClass) => {
    const profile = styleProfile(item)
    if (!profile) return []

    if (profile.role_ids.length > 0) {
      return profile.role_ids
    }

    return profile.main_role === null ? [] : [profile.main_role]
  }

  const classAttendState = (item: GroupClass): ClassAttendState => {
    const profile = styleProfile(item)
    const roleIds = availableRoleIds(item)

    return classOverrides[item.id] ?? {
      attending: item.booking_status !== null,
      bookingId: item.booking_id,
      status: item.booking_status,
      roleId:
        item.booking_role_id ??
        profile?.main_role ??
        roleIds[0] ??
        null,
    }
  }

  const toggleEvent = async (event: DanceEvent, attending: boolean) => {
    const key = `event:${event.id}`
    const previous = eventAttending(event)

    setActionError(null)
    setEventOverrides((current) => ({ ...current, [event.id]: attending }))
    setPendingActions((current) => ({ ...current, [key]: true }))

    try {
      const actual = await setEventAttending(event.id, attending)
      setEventOverrides((current) => ({ ...current, [event.id]: actual }))
    } catch (error) {
      setEventOverrides((current) => ({ ...current, [event.id]: previous }))
      setActionError(error instanceof Error ? error.message : String(error))
    } finally {
      setPendingActions((current) => ({ ...current, [key]: false }))
    }
  }

  const toggleClass = async (item: GroupClass, attending: boolean) => {
    const key = `class:${item.id}`
    const previous = classAttendState(item)

    setActionError(null)
    setClassOverrides((current) => ({
      ...current,
      [item.id]: {
        attending,
        bookingId: previous.bookingId,
        status: attending ? previous.status : null,
        roleId: previous.roleId,
      },
    }))
    setPendingActions((current) => ({ ...current, [key]: true }))

    try {
      const actual = await setClassAttending({
        slotId: item.id,
        bookingId: previous.bookingId,
        roleId: previous.roleId,
        attending,
      })

      setClassOverrides((current) => ({
        ...current,
        [item.id]: {
          attending: actual.attending,
          bookingId: actual.bookingId,
          status: actual.status,
          roleId: actual.roleId,
        },
      }))
    } catch (error) {
      setClassOverrides((current) => ({ ...current, [item.id]: previous }))
      setActionError(error instanceof Error ? error.message : String(error))
    } finally {
      setPendingActions((current) => ({ ...current, [key]: false }))
    }
  }

  const cycleClassRole = async (item: GroupClass) => {
    const roleIds = availableRoleIds(item)
    if (roleIds.length < 2) return

    const key = `class:${item.id}`
    const previous = classAttendState(item)
    const currentIndex = Math.max(0, roleIds.indexOf(previous.roleId ?? roleIds[0]))
    const nextRoleId = roleIds[(currentIndex + 1) % roleIds.length]

    setActionError(null)
    setClassOverrides((current) => ({
      ...current,
      [item.id]: {
        ...previous,
        roleId: nextRoleId,
      },
    }))

    if (!previous.attending || !previous.bookingId) {
      return
    }

    setPendingActions((current) => ({ ...current, [key]: true }))

    try {
      const actualRoleId = await changeClassBookingRole(
        previous.bookingId,
        nextRoleId,
      )

      setClassOverrides((current) => ({
        ...current,
        [item.id]: {
          ...previous,
          roleId: actualRoleId,
        },
      }))
    } catch (error) {
      setClassOverrides((current) => ({ ...current, [item.id]: previous }))
      setActionError(error instanceof Error ? error.message : String(error))
    } finally {
      setPendingActions((current) => ({ ...current, [key]: false }))
    }
  }

  return (
    <>
      {actionError && (
        <div className="tgui-error quick-attend-error">
          {actionError}
        </div>
      )}

      {state.data.attention.length > 0 && (
        <Section className="tgui-section dancer-home-attention">
          <List className="tgui-trip-list">
            {state.data.attention.map((item) => {
              const event = item.event
              const attending = event ? eventAttending(event) : false
              const pending = event
                ? Boolean(pendingActions[`event:${event.id}`])
                : false

              return (
                <Cell
                  key={item.id}
                  className="tgui-trip-cell quick-attend-cell"
                  before={<span className="dancer-home-pin" aria-hidden="true">📌</span>}
                  after={event ? (
                    <QuickAttendToggle
                      checked={attending}
                      pending={pending}
                      onChange={(checked) => {
                        void toggleEvent(event, checked)
                      }}
                    />
                  ) : undefined}
                  hint={event ? eventTypeLabel(event.event_type) : 'Важно'}
                  subtitle={
                    event
                      ? `${dateCaption(event.starts_at)} · ${timeRange(event.starts_at, event.ends_at)}`
                      : undefined
                  }
                  description={item.body ?? event?.description ?? undefined}
                >
                  {item.title}
                </Cell>
              )
            })}
          </List>
        </Section>
      )}

      <Section className="tgui-section" header="Сегодня">
        <List className="tgui-trip-list">
          {todayItems.length > 0 ? (
            todayItems.map((today) => {
              if (today.kind === 'event') {
                const attending = eventAttending(today.event)
                const pending = Boolean(
                  pendingActions[`event:${today.event.id}`],
                )

                return (
                  <Cell
                    key={`event-${today.event.id}`}
                    className="tgui-trip-cell quick-attend-cell"
                    before={<TimeBadge value={today.event.starts_at} />}
                    after={
                      <QuickAttendToggle
                        checked={attending}
                        pending={pending}
                        onChange={(checked) => {
                          void toggleEvent(today.event, checked)
                        }}
                      />
                    }
                    hint={eventTypeLabel(today.event.event_type)}
                    subtitle={today.event.venue?.name ?? undefined}
                    description={eventDescription(today.event)}
                  >
                    {today.event.title}
                  </Cell>
                )
              }

              const attend = classAttendState(today.item)
              const pending = Boolean(
                pendingActions[`class:${today.item.id}`],
              )

              return (
                <Cell
                  key={`class-${today.item.id}`}
                  className="tgui-trip-cell quick-attend-cell"
                  before={
                    <TimeBadge
                      value={today.item.starts_at}
                      balance={
                        today.item.style.is_partner_dance
                          ? today.item.role_balance
                          : null
                      }
                    />
                  }
                  after={
                    <QuickAttendToggle
                      checked={attend.attending}
                      pending={pending}
                      danger={attend.status === 'waitlisted'}
                      roleLabel={
                        availableRoleIds(today.item).length > 1
                          ? roleShortLabel(attend.roleId)
                          : null
                      }
                      onRoleChange={() => {
                        void cycleClassRole(today.item)
                      }}
                      onChange={(checked) => {
                        void toggleClass(today.item, checked)
                      }}
                    />
                  }
                  hint="Занятие"
                  subtitle={styleTitle(today.item.style) ?? undefined}
                  description={classDescription(today.item, attend.status)}
                >
                  {today.item.group_title}
                </Cell>
              )
            })
          ) : (
            <Cell subtitle="На сегодня событий и занятий нет.">
              Свободный день
            </Cell>
          )}
        </List>
      </Section>

      <Section className="tgui-section" header="Ближайшие события">
        <List className="tgui-trip-list">
          {visibleEvents.length > 0 ? (
            visibleEvents.map((event) => {
              const attending = eventAttending(event)
              const pending = Boolean(
                pendingActions[`event:${event.id}`],
              )

              return (
                <Cell
                  key={event.id}
                  className="tgui-trip-cell quick-attend-cell"
                  before={<DateBadge value={event.starts_at} />}
                  after={
                    <QuickAttendToggle
                      checked={attending}
                      pending={pending}
                      onChange={(checked) => {
                        void toggleEvent(event, checked)
                      }}
                    />
                  }
                  hint={eventTypeLabel(event.event_type)}
                  subtitle={eventSubtitle(event)}
                  description={eventDescription(event)}
                >
                  {event.title}
                </Cell>
              )
            })
          ) : (
            <Cell subtitle="Здесь появятся вечеринки и опены.">
              Событий пока нет
            </Cell>
          )}

          {hiddenEventCount > 0 && (
            <Cell
              Component="button"
              className="dancer-home-more-cell"
              after={<span className="menu-chevron">{eventsExpanded ? '⌃' : '⌄'}</span>}
              onClick={() => setEventsExpanded((value) => !value)}
            >
              {eventsExpanded
                ? 'Свернуть'
                : `Показать ещё ${hiddenEventCount}`}
            </Cell>
          )}
        </List>
      </Section>

      <Section className="tgui-section" header="Ближайшие занятия">
        <List className="tgui-trip-list">
          {state.data.classes.length > 0 ? (
            state.data.classes.map((item) => {
              const attend = classAttendState(item)
              const pending = Boolean(
                pendingActions[`class:${item.id}`],
              )

              return (
                <Cell
                  key={item.id}
                  className="tgui-trip-cell quick-attend-cell"
                  before={
                    <DateBadge
                      value={item.starts_at}
                      balance={
                        item.style.is_partner_dance
                          ? item.role_balance
                          : null
                      }
                    />
                  }
                  after={
                    <QuickAttendToggle
                      checked={attend.attending}
                      pending={pending}
                      danger={attend.status === 'waitlisted'}
                      roleLabel={
                        availableRoleIds(item).length > 1
                          ? roleShortLabel(attend.roleId)
                          : null
                      }
                      onRoleChange={() => {
                        void cycleClassRole(item)
                      }}
                      onChange={(checked) => {
                        void toggleClass(item, checked)
                      }}
                    />
                  }
                  hint="Занятие"
                  subtitle={classSubtitle(item)}
                  description={classDescription(item, attend.status)}
                >
                  {item.group_title}
                </Cell>
              )
            })
          ) : (
            <Cell subtitle="Появятся после добавления в группу и публикации расписания.">
              Занятий пока нет
            </Cell>
          )}
        </List>
      </Section>
    </>
  )
}

function InfoPage({ state }: { state: SchoolState }) {
  const [view, setView] = useState<SchoolView>('groups')

  if (state.status === 'idle' || state.status === 'loading') {
    return (
      <section className="tgui-page">
        <LoadingBlock text="Загружаю инфо" />
      </section>
    )
  }

  if (state.status === 'error') {
    return (
      <section className="tgui-page">
        <Placeholder header="Не удалось загрузить инфо" description={state.error} />
      </section>
    )
  }

  return (
    <section className="tgui-page dancer-school-page">
      <TabsList className="tgui-city-tabs dancer-school-tabs">
        <TabsList.Item selected={view === 'groups'} onClick={() => setView('groups')}>
          Группы
        </TabsList.Item>
        <TabsList.Item selected={view === 'trainers'} onClick={() => setView('trainers')}>
          Тренеры
        </TabsList.Item>
        <TabsList.Item selected={view === 'venues'} onClick={() => setView('venues')}>
          Залы
        </TabsList.Item>
        <TabsList.Item selected={view === 'styles'} onClick={() => setView('styles')}>
          Стили
        </TabsList.Item>
      </TabsList>

      {view === 'groups' && (
        <Section className="tgui-section">
          <List className="tgui-trip-list">
            {state.data.groups.length > 0 ? state.data.groups.map((group) => (
              <Cell
                key={group.id}
                className="tgui-trip-cell"
                hint={group.styleTitle}
                subtitle={group.level ?? undefined}
                description={[
                  group.enrollmentStatus === 'open' ? 'Набор открыт' : null,
                  group.maxCapacity ? `до ${group.maxCapacity} человек` : null,
                ].filter(Boolean).join(' · ') || undefined}
              >
                {group.title}
              </Cell>
            )) : (
              <Cell subtitle="Активных групп пока нет.">Группы</Cell>
            )}
          </List>
        </Section>
      )}

      {view === 'trainers' && (
        <Section className="tgui-section">
          <List className="tgui-trip-list">
            {state.data.trainers.length > 0 ? state.data.trainers.map((trainer) => (
              <Cell
                key={trainer.id}
                className="tgui-trip-cell"
                subtitle={trainer.groups.join(' · ') || undefined}
              >
                {trainer.name}
              </Cell>
            )) : (
              <Cell subtitle="Тренеры ещё не назначены группам.">Тренеры</Cell>
            )}
          </List>
        </Section>
      )}

      {view === 'venues' && (
        <Section className="tgui-section">
          <List className="tgui-trip-list">
            {state.data.venues.length > 0 ? state.data.venues.map((venue) => (
              <Cell
                key={venue.id}
                className="tgui-trip-cell"
                subtitle={venue.address ?? undefined}
                description={venue.capacity ? `До ${venue.capacity} человек` : undefined}
              >
                {venue.name}
              </Cell>
            )) : (
              <Cell subtitle="Залы пока не добавлены.">Залы</Cell>
            )}
          </List>
        </Section>
      )}

      {view === 'styles' && (
        <Section className="tgui-section">
          <List className="tgui-trip-list">
            {state.data.styles.length > 0 ? state.data.styles.map((style) => (
              <Cell
                key={style.id}
                className="tgui-trip-cell"
                hint={style.isPartnerDance ? 'Парный' : 'Соло'}
              >
                {style.title}
              </Cell>
            )) : (
              <Cell subtitle="Стили пока не добавлены.">Стили</Cell>
            )}
          </List>
        </Section>
      )}
    </section>
  )
}

function ProfilePage({ state }: { state: ProfileState }) {
  if (state.status === 'idle' || state.status === 'loading') {
    return (
      <section className="tgui-page">
        <LoadingBlock text="Загружаю профиль" />
      </section>
    )
  }

  if (state.status === 'error') {
    return (
      <section className="tgui-page">
        <Placeholder header="Не удалось загрузить профиль" description={state.error} />
      </section>
    )
  }

  const activeSubscription =
    state.data.subscriptions.find((item) => item.effectiveStatus === 'active')
    ?? state.data.subscriptions[0]
    ?? null

  return (
    <section className="tgui-page dancer-profile-page">
      <Section className="tgui-section" header="Абонемент">
        <List className="tgui-trip-list">
          {activeSubscription ? (
            <Cell
              className="tgui-trip-cell"
              hint={activeSubscription.effectiveStatus === 'active' ? 'Активен' : activeSubscription.effectiveStatus}
              subtitle={
                activeSubscription.endsAt
                  ? `до ${profileDate(activeSubscription.endsAt)}`
                  : `с ${profileDate(activeSubscription.startsAt)}`
              }
              description={[
                activeSubscription.remainingClasses !== null
                  ? `Осталось занятий: ${activeSubscription.remainingClasses}`
                  : null,
                activeSubscription.remainingSkips !== null
                  ? `Пропусков: ${activeSubscription.remainingSkips}`
                  : null,
              ].filter(Boolean).join(' · ') || undefined}
            >
              {activeSubscription.planName}
            </Cell>
          ) : (
            <Cell subtitle="Активного абонемента пока нет.">Абонемент</Cell>
          )}
        </List>
      </Section>

      <Section className="tgui-section" header="Посещённые занятия">
        <List className="tgui-trip-list">
          {state.data.attendedClasses.length > 0 ? state.data.attendedClasses.map((item) => (
            <Cell
              key={item.id}
              className="tgui-trip-cell"
              before={<DateBadge value={item.startsAt} />}
              subtitle={`${item.styleTitle} · ${timeRange(item.startsAt, item.endsAt)}`}
              description={item.venueName ?? undefined}
            >
              {item.groupTitle}
            </Cell>
          )) : (
            <Cell subtitle="Здесь появятся занятия с отметкой посещения.">
              Пока нет посещений
            </Cell>
          )}
        </List>
      </Section>

      <Section className="tgui-section" header="Посещённые мероприятия">
        <List className="tgui-trip-list">
          <Cell subtitle="Пока нет мероприятий с подтверждённым посещением.">
            Пока нет посещений
          </Cell>
        </List>
      </Section>
    </section>
  )
}

function NavIcon({ view }: { view: RootView }) {
  if (view === 'activities') {
    return (
      <svg className="dancer-nav-icon" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M7 3v3M17 3v3M4 9h16M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z" />
      </svg>
    )
  }

  if (view === 'info') {
    return (
      <svg className="dancer-nav-icon" viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="12" cy="12" r="9" />
        <path d="M12 10v6M12 7h.01" />
      </svg>
    )
  }

  return (
    <svg className="dancer-nav-icon" viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="8" r="4" />
      <path d="M5 21a7 7 0 0 1 14 0" />
    </svg>
  )
}

function viewTitle(view: RootView) {
  if (view === 'info') return 'Инфо'
  if (view === 'profile') return 'Профиль'
  return 'Активности'
}

export default function App() {
  const telegramUser = useMemo(
    () => getNativeTelegramUser() ?? getTelegramUser(),
    [],
  )

  const [auth, setAuth] = useState<AuthState>(initialAuth)
  const [role] = useState<AppRole>('dancer')
  const [view, setView] = useState<RootView>('info')
  const [loading, setLoading] = useState(true)
  const [feed, setFeed] = useState<FeedState>({
    status: 'idle',
    data: null,
    error: null,
  })
  const [school, setSchool] = useState<SchoolState>({
    status: 'idle',
    data: null,
    error: null,
  })
  const [profile, setProfile] = useState<ProfileState>({
    status: 'idle',
    data: null,
    error: null,
  })

  useEffect(() => {
    setTelegramVerticalSwipesEnabled(false)
  }, [])

  useEffect(() => {
    let cancelled = false

    void authenticateTelegram()
      .then((next) => {
        if (cancelled) return
        setAuth(next)
        if (next.status === 'authenticated') {
          setView('activities')
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })

    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (auth.status !== 'authenticated') return

    let cancelled = false
    setFeed({ status: 'loading', data: null, error: null })

    void loadDancerHomeFeed()
      .then((data) => {
        if (!cancelled) {
          setFeed({ status: 'ready', data, error: null })
        }
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setFeed({
            status: 'error',
            data: null,
            error: error instanceof Error ? error.message : String(error),
          })
        }
      })

    return () => {
      cancelled = true
    }
  }, [auth.status])

  useEffect(() => {
    if (view !== 'info') return

    let cancelled = false
    setSchool({ status: 'loading', data: null, error: null })

    void loadSchoolCatalog()
      .then((data) => {
        if (!cancelled) setSchool({ status: 'ready', data, error: null })
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setSchool({
            status: 'error',
            data: null,
            error: error instanceof Error ? error.message : String(error),
          })
        }
      })

    return () => {
      cancelled = true
    }
  }, [view])

  useEffect(() => {
    if (auth.status !== 'authenticated' || view !== 'profile') {
      return
    }

    let cancelled = false
    setProfile({ status: 'loading', data: null, error: null })

    void loadDancerProfileData()
      .then((data) => {
        if (!cancelled) setProfile({ status: 'ready', data, error: null })
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setProfile({
            status: 'error',
            data: null,
            error: error instanceof Error ? error.message : String(error),
          })
        }
      })

    return () => {
      cancelled = true
    }
  }, [auth.status, view])

  const showBottomNav = auth.status === 'authenticated' && !loading

  useEffect(() => {
    const root = document.documentElement

    if (!showBottomNav) {
      root.style.setProperty('--app-bottom-nav-height', '0px')
      return
    }

    const tabbar = document.querySelector<HTMLElement>('.tgui-bottom-nav')
    if (!tabbar) return

    const updateHeight = () => {
      root.style.setProperty(
        '--app-bottom-nav-height',
        `${tabbar.getBoundingClientRect().height}px`,
      )
    }

    updateHeight()
    const observer = new ResizeObserver(updateHeight)
    observer.observe(tabbar)

    return () => {
      observer.disconnect()
      root.style.setProperty('--app-bottom-nav-height', '0px')
    }
  }, [showBottomNav])

  const switchView = (next: RootView) => {
    setView(next)
    window.requestAnimationFrame(() => {
      document.querySelector<HTMLElement>('.app-shell > main')?.scrollTo({
        top: 0,
      })
    })
  }

  const buildLabel =
    __APP_COMMIT__ === 'local'
      ? 'local'
      : __APP_COMMIT__.slice(0, 8)

  const dancer =
    auth.status === 'authenticated'
      ? auth.context.dancer
      : null

  const name = useMemo(
    () => dancer ? displayName(dancer) : telegramDisplayName(telegramUser),
    [dancer, telegramUser],
  )

  const mainContent = () => {
    if (view === 'info') {
      return <InfoPage state={school} />
    }

    if (auth.status !== 'authenticated') {
      return <InfoPage state={school} />
    }

    if (view === 'profile') {
      return <ProfilePage state={profile} />
    }

    return (
      <section
        className={
          feed.status === 'ready' && feed.data.attention.length > 0
            ? 'tgui-page dancer-home-page has-attention'
            : 'tgui-page dancer-home-page'
        }
      >
        <DancerHome
          state={feed}
          dancerStyles={auth.context.styles}
        />
      </section>
    )
  }
  return (
    <div className={showBottomNav ? 'app-shell has-bottom-nav' : 'app-shell'}>
      <header className="topbar">
        <div>
          <div className="eyebrow">
            DANCERS <span className="build-inline">· {buildLabel}</span>
          </div>
          <h1>{viewTitle(view)}</h1>
        </div>

        {dancer || telegramUser ? (
          <div className="account-area">
            <button
              type="button"
              className="account-trigger"
              onClick={() => auth.status === 'authenticated' && switchView('profile')}
              aria-label="Открыть профиль"
            >
              <span className="account-copy">
                <strong>{name}</strong>
                <span>
                  {loading
                    ? 'Вход…'
                    : auth.status === 'authenticated'
                      ? roleLabels[role]
                      : 'Telegram'}
                </span>
              </span>
              <span className="avatar" aria-hidden="true">
                {telegramUser?.photo_url ? (
                  <img
                    src={telegramUser.photo_url}
                    alt=""
                    referrerPolicy="no-referrer"
                  />
                ) : dancer ? (
                  initials(dancer)
                ) : (
                  telegramInitials(telegramUser)
                )}
              </span>
            </button>
          </div>
        ) : null}
      </header>

      <main>{mainContent()}</main>

      {showBottomNav && (
        <Tabbar className="tgui-bottom-nav">
          <Tabbar.Item
            selected={view === 'activities'}
            text="Активности"
            onClick={() => switchView('activities')}
          >
            <NavIcon view="activities" />
          </Tabbar.Item>
          <Tabbar.Item
            selected={view === 'info'}
            text="Инфо"
            onClick={() => switchView('info')}
          >
            <NavIcon view="info" />
          </Tabbar.Item>
          <Tabbar.Item
            selected={view === 'profile'}
            text="Профиль"
            onClick={() => switchView('profile')}
          >
            <NavIcon view="profile" />
          </Tabbar.Item>
        </Tabbar>
      )}
    </div>
  )
}
