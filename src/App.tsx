import { useEffect, useMemo, useState } from 'react'
import {
  Cell,
  List,
  Placeholder,
  Section,
  Spinner,
} from '@telegram-apps/telegram-ui'
import {
  authenticateTelegram,
  type AuthState,
} from './lib/auth'
import type {
  AppRole,
  DancerSummary,
} from './lib/dancerContext'
import {
  loadDancerHomeFeed,
  type DanceEvent,
  type DancerHomeFeed,
  type GroupClass,
  type HomeStyle,
} from './lib/homeFeed'
import { getTelegramUser, setTelegramVerticalSwipesEnabled } from './lib/telegram'
import { getNativeTelegramUser, getTmaDiagnostics } from './lib/tma'

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

type FeedState =
  | { status: 'loading'; data: DancerHomeFeed | null; error: null }
  | { status: 'ready'; data: DancerHomeFeed; error: null }
  | { status: 'error'; data: null; error: string }

type TodayItem =
  | { kind: 'event'; startsAt: string; event: DanceEvent }
  | { kind: 'class'; startsAt: string; item: GroupClass }

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

function classDescription(item: GroupClass) {
  return [
    item.group_level,
    item.venue?.name,
    item.booking_status === 'booked'
      ? 'Записан'
      : item.booking_status === 'waitlisted'
        ? 'Лист ожидания'
        : null,
  ].filter(Boolean).join(' · ') || undefined
}

function DateBadge({ value }: { value: string }) {
  const parts = dateParts(value)

  return (
    <span className="tgui-trip-date">
      <strong>{parts.day}</strong>
      <span>{parts.weekday}</span>
    </span>
  )
}

function TimeBadge({ value }: { value: string }) {
  return (
    <span className="dancer-home-time">
      {shortTime(value)}
    </span>
  )
}

function DancerHome({ state }: { state: FeedState }) {
  const [eventsExpanded, setEventsExpanded] = useState(false)

  if (state.status === 'loading') {
    return (
      <Placeholder
        header="Загружаю"
        description="Получаем ближайшие события и занятия."
      >
        <Spinner size="m" />
      </Placeholder>
    )
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

  return (
    <>
      {state.data.attention.length > 0 && (
        <Section className="tgui-section" header="Внимание">
          <List className="tgui-trip-list">
            {state.data.attention.map((item) => (
              <Cell
                key={item.id}
                className="tgui-trip-cell"
                before={<span className="dancer-home-pin" aria-hidden="true">📌</span>}
                hint={item.event ? eventTypeLabel(item.event.event_type) : 'Важно'}
                subtitle={
                  item.event
                    ? `${dateCaption(item.event.starts_at)} · ${timeRange(item.event.starts_at, item.event.ends_at)}`
                    : undefined
                }
                description={item.body ?? item.event?.description ?? undefined}
              >
                {item.title}
              </Cell>
            ))}
          </List>
        </Section>
      )}

      <Section className="tgui-section" header="Сегодня">
        <List className="tgui-trip-list">
          {todayItems.length > 0 ? (
            todayItems.map((today) => (
              today.kind === 'event' ? (
                <Cell
                  key={`event-${today.event.id}`}
                  className="tgui-trip-cell"
                  before={<TimeBadge value={today.event.starts_at} />}
                  hint={eventTypeLabel(today.event.event_type)}
                  subtitle={today.event.venue?.name ?? undefined}
                  description={eventDescription(today.event)}
                >
                  {today.event.title}
                </Cell>
              ) : (
                <Cell
                  key={`class-${today.item.id}`}
                  className="tgui-trip-cell"
                  before={<TimeBadge value={today.item.starts_at} />}
                  hint="Занятие"
                  subtitle={styleTitle(today.item.style) ?? undefined}
                  description={classDescription(today.item)}
                >
                  {today.item.group_title}
                </Cell>
              )
            ))
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
            visibleEvents.map((event) => (
              <Cell
                key={event.id}
                className="tgui-trip-cell"
                before={<DateBadge value={event.starts_at} />}
                hint={eventTypeLabel(event.event_type)}
                subtitle={eventSubtitle(event)}
                description={eventDescription(event)}
              >
                {event.title}
              </Cell>
            ))
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
            state.data.classes.map((item) => (
              <Cell
                key={item.id}
                className="tgui-trip-cell"
                before={<DateBadge value={item.starts_at} />}
                hint="Занятие"
                subtitle={classSubtitle(item)}
                description={classDescription(item)}
              >
                {item.group_title}
              </Cell>
            ))
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

export default function App() {
  const telegramUser = useMemo(
    () => getNativeTelegramUser() ?? getTelegramUser(),
    [],
  )

  const [auth, setAuth] = useState<AuthState>(initialAuth)
  const [role] = useState<AppRole>('dancer')
  const [loading, setLoading] = useState(true)
  const [feed, setFeed] = useState<FeedState>({
    status: 'loading',
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
        if (!cancelled) setAuth(next)
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

  const tma = getTmaDiagnostics()
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

  return (
    <div className="app-shell">
      <header className="topbar">
        <div>
          <div className="eyebrow">
            DANCERS <span className="build-inline">· {buildLabel}</span>
          </div>
          <h1>События</h1>
        </div>

        {dancer || telegramUser ? (
          <div className="account-area">
            <div className="account-trigger">
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
            </div>
          </div>
        ) : null}
      </header>

      <main>
        <section className="tgui-page">
          {loading ? (
            <Placeholder
              header="Авторизация…"
              description="Проверяем Telegram и создаём сессию DanceApp."
            >
              <Spinner size="m" />
            </Placeholder>
          ) : auth.status === 'error' ? (
            <>
              <Placeholder
                header="Не удалось войти"
                description={auth.error}
              />
              <Section className="tgui-section" header="Диагностика">
                <Cell>
                  Runtime: {tma.isTelegram ? 'Telegram' : 'browser'}
                </Cell>
                <Cell>
                  TMA: {tma.initialized ? 'initialized' : tma.error || 'not initialized'}
                </Cell>
                <Cell>Build: {buildLabel}</Cell>
              </Section>
            </>
          ) : auth.status === 'preview' ? (
            <Placeholder
              header="Browser preview"
              description="Откройте Mini App из Telegram, чтобы увидеть персональные события и занятия."
            />
          ) : (
            <DancerHome state={feed} />
          )}
        </section>
      </main>
    </div>
  )
}
