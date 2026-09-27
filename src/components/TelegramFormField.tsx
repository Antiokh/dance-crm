import type { ReactNode } from 'react'

export default function TelegramFormField({
  label,
  children,
  full = false,
}: {
  label: string
  children: ReactNode
  full?: boolean
}) {
  return (
    <div className={full ? 'tgui-form-field tgui-form-full-row' : 'tgui-form-field'}>
      <span className="tgui-form-field-label">{label}</span>
      {children}
    </div>
  )
}
