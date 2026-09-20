import { useEffect } from 'react'

export default function Modal({
  open,
  title,
  onClose,
  children,
  footer,
  width,
  drawer = false,
  closeOnOverlay = true
}) {
  useEffect(() => {
    if (!open) return undefined
    const handler = (event) => {
      if (event.key === 'Escape') onClose?.()
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [open, onClose])

  if (!open) return null

  const panelClass = drawer ? 'drawer' : `modal ${width === 'wide' ? 'wide' : ''}`

  return (
    <div
      className={`overlay ${drawer ? 'drawer-overlay' : ''}`}
      onClick={closeOnOverlay ? (event) => event.target === event.currentTarget && onClose?.() : undefined}
    >
      <div className={panelClass} role="dialog" aria-modal="true">
        <div className="modal-header">
          <h3>{title}</h3>
          <button type="button" className="icon-btn" onClick={onClose} aria-label="关闭">
            ×
          </button>
        </div>
        <div className="modal-body">{children}</div>
        {footer ? <div className="modal-footer">{footer}</div> : null}
      </div>
    </div>
  )
}
