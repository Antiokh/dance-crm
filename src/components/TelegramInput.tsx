import { Input, type InputProps } from '@telegram-apps/telegram-ui'
import { useRef } from 'react'

function PickerIcon({ type }: { type: 'date' | 'time' | 'datetime-local' }) {
  if (type === 'time') {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="12" cy="12" r="8" />
        <path d="M12 7v5l3 2" />
      </svg>
    )
  }

  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M6 3v3M18 3v3M4 9h16M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z" />
    </svg>
  )
}

export default function TelegramInput({
  className,
  type,
  after,
  ...props
}: InputProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const pickerType =
    type === 'date'
    || type === 'time'
    || type === 'datetime-local'
  const classes = [
    'telegram-form-control',
    pickerType ? 'telegram-form-control-native-picker' : '',
    className,
  ].filter(Boolean).join(' ')

  const openNativePicker = () => {
    const input = inputRef.current
    if (!input) return

    try {
      input.showPicker?.()
    } catch {
      input.focus()
      input.click()
    }
  }

  const pickerButton = pickerType ? (
    <button
      type="button"
      className="telegram-input-picker-button"
      aria-label="Выбрать дату и время"
      onMouseDown={(event) => event.preventDefault()}
      onClick={(event) => {
        event.stopPropagation()
        openNativePicker()
      }}
    >
      <PickerIcon type={type as 'date' | 'time' | 'datetime-local'} />
    </button>
  ) : undefined

  return (
    <Input
      ref={inputRef}
      className={classes}
      type={type}
      after={after ?? pickerButton}
      {...props}
    />
  )
}
