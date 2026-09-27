export default function SheetCloseButton({
  onClick,
}: {
  onClick: () => void
}) {
  return (
    <button
      type="button"
      className="tgui-sheet-close"
      onClick={onClick}
      aria-label="Закрыть"
    >
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="m6 6 12 12M18 6 6 18" />
      </svg>
    </button>
  )
}
