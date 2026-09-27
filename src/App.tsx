import { useEffect, useMemo, useState } from 'react'
import {
  Cell,
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
  DanceStyle,
  DancerSummary,
} from './lib/dancerContext'
import { getTelegramUser } from './lib/telegram'
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

function highestAvailableRole(roles: AppRole[]): AppRole {
  if (roles.includes('administrator')) return 'administrator'
  if (roles.includes('trainer')) return 'trainer'
  return 'dancer'
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

function styleTitle(style: DanceStyle) {
  return (
    style.title_ru?.trim() ||
    style.title_en?.trim() ||
    style.title_sr?.trim() ||
    `Style #${style.id}`
  )
}

export default function App() {
  const telegramUser = useMemo(
    () => getNativeTelegramUser() ?? getTelegramUser(),
    [],
  )
  const [auth, setAuth] = useState<AuthState>(initialAuth)
  const [role, setRole] = useState<AppRole>('dancer')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false

    void authenticateTelegram()
      .then((next) => {
        if (cancelled) return
        setAuth(next)
        if (next.status === 'authenticated') {
          setRole(highestAvailableRole(next.context.roles))
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })

    return () => {
      cancelled = true
    }
  }, [])

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
    <main className="app-shell">
      <header className="topbar">
        <div>
          <div className="eyebrow">
            DANCERS <span className="build-inline">· {buildLabel}</span>
          </div>
          <h1>Профиль</h1>
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

      <section className="tgui-page auth-shell-page">
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
            <>
              <Placeholder
                header="Browser preview"
                description="Интерфейс загружен. Откройте Mini App из Telegram, чтобы проверить реальную авторизацию."
              />
              <Section className="tgui-section" header="Runtime">
                <Cell>DanceApp: configured</Cell>
                <Cell>
                  TMA: {tma.isTelegram ? 'Telegram detected' : 'browser preview'}
                </Cell>
                <Cell>Build: {buildLabel}</Cell>
              </Section>
            </>
          ) : (
            <>
              <Section className="tgui-section" header="Авторизация">
                <Cell
                  subtitle={
                    dancer?.telegram_username
                      ? `@${dancer.telegram_username}`
                      : 'Telegram'
                  }
                  after={<strong>OK</strong>}
                >
                  {name}
                </Cell>
                <Cell
                  subtitle="Supabase Auth session"
                  after={<span className="auth-ok">Активна</span>}
                >
                  DanceApp
                </Cell>
                <Cell
                  subtitle={String(dancer?.telegram_id ?? '—')}
                  after={<span>{auth.context.roles.length}</span>}
                >
                  Telegram ID · ролей
                </Cell>
              </Section>

              <Section className="tgui-section" header="Роли">
                {auth.context.roles.map((role) => (
                  <Cell key={role}>{roleLabels[role]}</Cell>
                ))}
              </Section>

              <Section className="tgui-section" header="Танцевальные стили">
                {auth.context.styles.length > 0 ? (
                  <div className="auth-style-list">
                    {auth.context.styles.map((style) => (
                      <span className="auth-style-pill" key={style.id}>
                        {styleTitle(style)}
                      </span>
                    ))}
                  </div>
                ) : (
                  <Cell subtitle="Профиль авторизован, стили пока не выбраны.">
                    Нет выбранных стилей
                  </Cell>
                )}
              </Section>

              <Section className="tgui-section" header="Runtime">
                <Cell>
                  TMA: {tma.initialized ? 'initialized' : 'fallback'}
                </Cell>
                <Cell>Build: {buildLabel}</Cell>
              </Section>
            </>
          )}
      </section>
    </main>
  )
}
