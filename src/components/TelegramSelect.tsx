import type { SelectHTMLAttributes } from 'react'

export default function TelegramSelect({
  className,
  children,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement>) {
  const classes = [
    'telegram-form-control',
    'telegram-select-control',
    className,
  ].filter(Boolean).join(' ')

  return (
    <div className={classes}>
      <select className="telegram-select-native" {...props}>
        {children}
      </select>
      <svg
        className="telegram-select-chevron"
        viewBox="0 0 24 24"
        aria-hidden="true"
      >
        <path d="m7 9.5 5 5 5-5" />
      </svg>
    </div>
  )
}
