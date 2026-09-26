export type TelegramUser = {
  id: number
  first_name?: string
  last_name?: string
  username?: string
  photo_url?: string
  language_code?: string
  is_premium?: boolean
}

type TelegramPopupButton = {
  id?: string
  type?: 'default' | 'ok' | 'close' | 'cancel' | 'destructive'
  text?: string
}

type TelegramBackButton = {
  isVisible?: boolean
  show?: () => void
  hide?: () => void
  onClick?: (callback: () => void) => void
  offClick?: (callback: () => void) => void
}

type TelegramWebApp = {
  initData?: string
  initDataUnsafe?: {
    user?: TelegramUser
    start_param?: string
  }
  BackButton?: TelegramBackButton
  close?: () => void
  disableVerticalSwipes?: () => void
  enableVerticalSwipes?: () => void
  showAlert?: (message: string, callback?: () => void) => void
  showConfirm?: (message: string, callback?: (confirmed: boolean) => void) => void
  showPopup?: (
    params: { title?: string; message: string; buttons?: TelegramPopupButton[] },
    callback?: (buttonId: string) => void,
  ) => void
  openTelegramLink?: (url: string) => void
}

function getTelegramWebApp() {
  return (
    window as typeof window & { Telegram?: { WebApp?: TelegramWebApp } }
  ).Telegram?.WebApp
}

export function getTelegramInitData(): string {
  return getTelegramWebApp()?.initData ?? ''
}

export function getTelegramUser(): TelegramUser | null {
  return getTelegramWebApp()?.initDataUnsafe?.user ?? null
}

export function getTelegramStartParam(): string {
  return getTelegramWebApp()?.initDataUnsafe?.start_param
    ?? new URLSearchParams(window.location.search).get('tgWebAppStartParam')
    ?? ''
}

export function setTelegramVerticalSwipesEnabled(enabled: boolean) {
  const webApp = getTelegramWebApp()
  if (enabled) webApp?.enableVerticalSwipes?.()
  else webApp?.disableVerticalSwipes?.()
}

export function showTelegramNotice(message: string, title = 'Готово') {
  const webApp = getTelegramWebApp()
  if (webApp?.showPopup) {
    webApp.showPopup({ title, message, buttons: [{ type: 'ok' }] })
    return
  }
  if (webApp?.showAlert) {
    webApp.showAlert(message)
    return
  }
  window.alert(message)
}

export function showTelegramConfirm(message: string): Promise<boolean> {
  const webApp = getTelegramWebApp()
  if (webApp?.showConfirm) {
    return new Promise((resolve) => webApp.showConfirm?.(message, resolve))
  }
  if (webApp?.showPopup) {
    return new Promise((resolve) => {
      webApp.showPopup?.({
        title: 'Подтвердите',
        message,
        buttons: [
          { id: 'delete', type: 'destructive', text: 'Удалить' },
          { id: 'cancel', type: 'cancel' },
        ],
      }, (buttonId) => resolve(buttonId === 'delete'))
    })
  }
  return Promise.resolve(window.confirm(message))
}

const BACK_GUARD_KEY = '__dobriTelegramBackGuard'
let telegramBackNavigationInstalled = false

/**
 * Connect Telegram's native BackButton and Android/browser Back to the current
 * in-app state. Root tabs are peers; nested screens and overlays unwind first.
 */
export function setupTelegramBackNavigation() {
  const webApp = getTelegramWebApp()
  if (!webApp || telegramBackNavigationInstalled) return
  telegramBackNavigationInstalled = true

  const nativeBack = webApp.BackButton
  if (nativeBack?.show && nativeBack?.hide) {
    document.documentElement.classList.add('telegram-native-back')
  }

  const ensureHistoryGuard = () => {
    const state = history.state as Record<string, unknown> | null
    if (state?.[BACK_GUARD_KEY]) return
    history.pushState({ ...(state ?? {}), [BACK_GUARD_KEY]: true }, '', window.location.href)
  }

  const findInternalBackAction = (): (() => void) | null => {
    const calendarBackdrop = document.querySelector<HTMLButtonElement>('.calendar-menu-backdrop')
    if (calendarBackdrop) return () => calendarBackdrop.click()

    const accountBackdrop = document.querySelector<HTMLButtonElement>('.account-menu-backdrop')
    if (accountBackdrop) return () => accountBackdrop.click()

    const sheetClose = document.querySelector<HTMLButtonElement>('.sheet-backdrop .tgui-sheet-close')
    if (sheetClose) return () => sheetClose.click()

    const pageBack = document.querySelector<HTMLButtonElement>('main button.back')
    if (pageBack) return () => pageBack.click()

    if (document.querySelector('.profile-page')) {
      const tripsTab = document.querySelector<HTMLButtonElement>('.bottom-nav button:first-child')
      if (tripsTab) return () => tripsTab.click()
    }

    return null
  }

  const syncNativeBackButton = () => {
    if (!nativeBack?.show || !nativeBack?.hide) return
    if (findInternalBackAction()) nativeBack.show()
    else nativeBack.hide()
  }

  const goBackInsideApp = () => {
    const action = findInternalBackAction()
    if (!action) return false
    action()
    window.setTimeout(syncNativeBackButton, 0)
    return true
  }

  const onTelegramBack = () => {
    goBackInsideApp()
  }

  const onBrowserBack = () => {
    if (goBackInsideApp()) {
      ensureHistoryGuard()
      return
    }

    // At the app root there is nowhere meaningful to go back to.
    webApp.close?.()
  }

  nativeBack?.onClick?.(onTelegramBack)
  window.addEventListener('popstate', onBrowserBack)

  const observer = new MutationObserver(syncNativeBackButton)
  observer.observe(document.body, { childList: true, subtree: true })

  ensureHistoryGuard()
  syncNativeBackButton()
}

export function getTelegramDisplayName(user: TelegramUser | null): string {
  if (!user) return 'Пользователь'

  const fullName = [user.first_name, user.last_name]
    .filter((part): part is string => Boolean(part?.trim()))
    .join(' ')
    .trim()

  if (fullName) return fullName
  if (user.username) return `@${user.username}`
  return 'Пользователь'
}

export function getTelegramInitials(user: TelegramUser | null): string {
  if (!user) return 'TG'

  const initials = [user.first_name, user.last_name]
    .filter((part): part is string => Boolean(part?.trim()))
    .slice(0, 2)
    .map((part) => part.trim().charAt(0).toUpperCase())
    .join('')

  if (initials) return initials
  if (user.username) return user.username.slice(0, 2).toUpperCase()
  return 'TG'
}


export function openTelegramUsername(username: string) {
  const normalized = username.trim().replace(/^@/, '')
  if (!normalized) return

  const url = `https://t.me/${encodeURIComponent(normalized)}`
  const webApp = getTelegramWebApp()

  if (webApp?.openTelegramLink) {
    try {
      webApp.openTelegramLink(url)
      return
    } catch {
      // Fall through to a regular browser navigation.
    }
  }

  window.open(url, '_blank', 'noopener,noreferrer')
}


export function showTelegramActionConfirm({
  title,
  message,
  confirmText = 'Подтвердить',
  destructive = false,
}: {
  title: string
  message: string
  confirmText?: string
  destructive?: boolean
}): Promise<boolean> {
  const webApp = getTelegramWebApp()

  if (webApp?.showPopup) {
    return new Promise((resolve) => {
      webApp.showPopup?.({
        title,
        message,
        buttons: [
          {
            id: 'confirm',
            type: destructive ? 'destructive' : 'default',
            text: confirmText,
          },
          { id: 'cancel', type: 'cancel' },
        ],
      }, (buttonId) => resolve(buttonId === 'confirm'))
    })
  }

  if (webApp?.showConfirm) {
    return new Promise((resolve) => webApp.showConfirm?.(message, resolve))
  }

  return Promise.resolve(window.confirm(message))
}
