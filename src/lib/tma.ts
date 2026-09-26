import {
  backButton,
  init,
  isTMA,
  miniApp,
  popup,
  retrieveLaunchParams,
  retrieveRawInitData,
  themeParams,
  viewport,
  type ShowOptionsButton,
} from '@tma.js/sdk'

type Insets = {
  top: number
  right: number
  bottom: number
  left: number
}

export type AppAppearance = 'light' | 'dark'

export type TmaDiagnostics = {
  isTelegram: boolean
  initialized: boolean
  platform?: string
  version?: string
  error?: string
}

const appearanceListeners = new Set<() => void>()
let appearance: AppAppearance =
  window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'

let diagnostics: TmaDiagnostics = {
  isTelegram: false,
  initialized: false,
}

let rawInitData: string | undefined
let started = false

export type NativeTelegramUser = {
  id: number
  first_name?: string
  last_name?: string
  username?: string
  photo_url?: string
  language_code?: string
  is_premium?: boolean
}

type NativeTelegramWebApp = {
  initData?: string
  initDataUnsafe?: {
    user?: NativeTelegramUser
  }
}

function getNativeTelegramWebApp() {
  return (
    window as typeof window & {
      Telegram?: { WebApp?: NativeTelegramWebApp }
    }
  ).Telegram?.WebApp
}

function getNativeRawInitData(): string | undefined {
  const value = getNativeTelegramWebApp()?.initData?.trim()
  return value || undefined
}

export function getNativeTelegramUser(): NativeTelegramUser | null {
  return getNativeTelegramWebApp()?.initDataUnsafe?.user ?? null
}
let currentBackHandler: (() => void) | undefined
let unsubscribeBackButton: (() => void) | undefined

function setAppearance(next: AppAppearance) {
  if (appearance !== next) {
    appearance = next
    appearanceListeners.forEach((listener) => listener())
  }

  document.documentElement.dataset.appAppearance = next
  document.documentElement.style.colorScheme = next
}

function syncBrowserAppearance() {
  const media = window.matchMedia?.('(prefers-color-scheme: dark)')
  setAppearance(media?.matches ? 'dark' : 'light')
}

function syncTmaAppearance() {
  setAppearance(themeParams.isDark() ? 'dark' : 'light')
}

function setInsets(prefix: string, insets: Insets) {
  const style = document.documentElement.style
  style.setProperty(`--tg-${prefix}-inset-top`, `${insets.top}px`)
  style.setProperty(`--tg-${prefix}-inset-right`, `${insets.right}px`)
  style.setProperty(`--tg-${prefix}-inset-bottom`, `${insets.bottom}px`)
  style.setProperty(`--tg-${prefix}-inset-left`, `${insets.left}px`)
}

function syncViewportInsets() {
  if (!viewport.isMounted()) return
  setInsets('safe-area', viewport.safeAreaInsets())
  setInsets('content-safe-area', viewport.contentSafeAreaInsets())
}

function syncTelegramChrome() {
  const backgroundColor = themeParams.secondaryBgColor() ?? themeParams.bgColor()
  const headerColor = themeParams.headerBgColor() ?? themeParams.bgColor()
  const bottomBarColor =
    themeParams.bottomBarBgColor() ??
    themeParams.secondaryBgColor() ??
    themeParams.bgColor()

  syncTmaAppearance()

  const themeMeta = document.querySelector('meta[name="theme-color"]')
  if (themeMeta && backgroundColor) {
    themeMeta.setAttribute('content', backgroundColor)
  }

  if (headerColor && miniApp.setHeaderColor.isAvailable()) {
    if (miniApp.setHeaderColor.supports('rgb')) {
      miniApp.setHeaderColor(headerColor)
    } else {
      miniApp.setHeaderColor('bg_color')
    }
  }

  if (backgroundColor && miniApp.setBgColor.isAvailable()) {
    miniApp.setBgColor(backgroundColor)
  }

  if (bottomBarColor && miniApp.setBottomBarColor.isAvailable()) {
    miniApp.setBottomBarColor(bottomBarColor)
  }
}

function initializeBackButton() {
  if (!backButton.mount.isAvailable()) return

  backButton.mount()

  unsubscribeBackButton?.()
  unsubscribeBackButton = backButton.onClick(() => {
    currentBackHandler?.()
  })

  if (backButton.hide.isAvailable()) {
    backButton.hide()
  }
}

export function initializeTma(): TmaDiagnostics {
  if (started) return diagnostics
  started = true

  if (!isTMA()) {
    document.documentElement.dataset.tmaEnvironment = 'browser'
    syncBrowserAppearance()

    const media = window.matchMedia?.('(prefers-color-scheme: dark)')
    media?.addEventListener?.('change', syncBrowserAppearance)

    diagnostics = {
      isTelegram: false,
      initialized: false,
    }
    return diagnostics
  }

  try {
    document.documentElement.dataset.tmaEnvironment = 'telegram'
    init()

    const launchParams = retrieveLaunchParams()
    rawInitData = getNativeRawInitData() ?? retrieveRawInitData()

    diagnostics = {
      isTelegram: true,
      initialized: true,
      platform: launchParams.tgWebAppPlatform,
      version: launchParams.tgWebAppVersion,
    }

    themeParams.mount()
    if (!themeParams.isCssVarsBound()) {
      themeParams.bindCssVars()
    }

    miniApp.mount()
    syncTelegramChrome()
    themeParams.state.sub(syncTelegramChrome)
    themeParams.isDark.sub(syncTmaAppearance)

    initializeBackButton()

    if (miniApp.ready.isAvailable()) {
      miniApp.ready()
    }

    if (viewport.mount.isAvailable()) {
      void viewport
        .mount()
        .then(() => {
          if (!viewport.isCssVarsBound()) {
            viewport.bindCssVars()
          }

          syncViewportInsets()
          viewport.safeAreaInsets.sub(syncViewportInsets)
          viewport.contentSafeAreaInsets.sub(syncViewportInsets)

          if (viewport.expand.isAvailable()) {
            viewport.expand()
          }
        })
        .catch((error: unknown) => {
          console.warn('TMA viewport initialization failed', error)
        })
    }
  } catch (error) {
    diagnostics = {
      isTelegram: true,
      initialized: false,
      error: error instanceof Error ? error.message : String(error),
    }

    console.warn('TMA SDK initialization failed', error)
  }

  return diagnostics
}

export function getTmaDiagnostics(): TmaDiagnostics {
  return diagnostics
}

export function getAppAppearance(): AppAppearance {
  return appearance
}

export function subscribeAppAppearance(listener: () => void): () => void {
  appearanceListeners.add(listener)
  return () => appearanceListeners.delete(listener)
}

export function getTmaRawInitData(): string | undefined {
  return getNativeRawInitData() ?? rawInitData
}

export function setTmaBackHandler(handler?: () => void) {
  currentBackHandler = handler

  if (!diagnostics.initialized || !backButton.isMounted()) return

  if (handler) {
    if (backButton.show.isAvailable()) backButton.show()
  } else if (backButton.hide.isAvailable()) {
    backButton.hide()
  }
}

export type TmaPopupButton = ShowOptionsButton

export async function showTmaPopup(options: {
  title?: string
  message: string
  buttons: TmaPopupButton[]
}): Promise<{ available: boolean; buttonId?: string }> {
  if (!diagnostics.initialized || !popup.isSupported() || !popup.show.isAvailable()) {
    return { available: false }
  }

  try {
    const buttonId = await popup.show(options)
    return { available: true, buttonId }
  } catch (error) {
    console.warn('TMA popup failed', error)
    return { available: false }
  }
}
