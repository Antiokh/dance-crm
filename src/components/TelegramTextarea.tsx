import type { TextareaHTMLAttributes } from 'react'

export default function TelegramTextarea({
  className,
  ...props
}: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const classes = ['telegram-textarea-control', className]
    .filter(Boolean)
    .join(' ')

  return <textarea className={classes} {...props} />
}
