import {
  StrictMode,
  type CSSProperties,
  useSyncExternalStore,
} from 'react'
import { createRoot } from 'react-dom/client'
import { AppRoot } from '@telegram-apps/telegram-ui'
import App from './App'
import {
  getAppAppearance,
  initializeTma,
  subscribeAppAppearance,
} from './lib/tma'
import './styles.css'
import './telegram-navigation.css'
import '@telegram-apps/telegram-ui/dist/styles.css'
import './telegram-ui.css'
import './auth-shell.css'
import './admin.css'

initializeTma()

const telegramUiThemeFixes = {
  '--tgui--tertiary_bg_color':
    'var(--tg-theme-secondary-bg-color, #f2f4f7)',
  '--tgui--segmented_control_active_bg':
    'var(--tg-theme-bg-color, #ffffff)',
} as CSSProperties

function Root() {
  const appearance = useSyncExternalStore(
    subscribeAppAppearance,
    getAppAppearance,
    getAppAppearance,
  )

  return (
    <AppRoot
      platform="ios"
      appearance={appearance}
      style={telegramUiThemeFixes}
      className="telegram-ui-root"
    >
      <App />
    </AppRoot>
  )
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Root />
  </StrictMode>,
)
