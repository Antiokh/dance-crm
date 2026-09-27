import { Switch, type SwitchProps } from '@telegram-apps/telegram-ui'

export default function TelegramSwitch({ className, ...props }: SwitchProps) {
  const classes = ['telegram-switch', className].filter(Boolean).join(' ')
  return <Switch className={classes} {...props} />
}
