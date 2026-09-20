import { createContext, useCallback, useContext, useMemo, useState } from 'react'

const ToastContext = createContext(null)

const ICONS = { success: '✅', error: '⛔', warning: '⚠️', info: 'ℹ️' }

export function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([])

  const remove = useCallback((id) => {
    setToasts((list) => list.filter((item) => item.id !== id))
  }, [])

  const push = useCallback(
    (message, tone = 'info', timeout = 3600) => {
      const id = `${Date.now()}-${Math.random().toString(16).slice(2)}`
      setToasts((list) => [...list.slice(-3), { id, message, tone }])
      if (timeout) window.setTimeout(() => remove(id), timeout)
      return id
    },
    [remove]
  )

  const api = useMemo(
    () => ({
      push,
      remove,
      success: (message, timeout) => push(message, 'success', timeout),
      error: (message, timeout) => push(message, 'error', timeout ?? 5200),
      warning: (message, timeout) => push(message, 'warning', timeout),
      info: (message, timeout) => push(message, 'info', timeout)
    }),
    [push, remove]
  )

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div className="toast-stack">
        {toasts.map((item) => (
          <div key={item.id} className={`toast ${item.tone}`} role="status">
            <span>{ICONS[item.tone] || ICONS.info}</span>
            <span style={{ flex: 1 }}>{item.message}</span>
            <button type="button" className="icon-btn" onClick={() => remove(item.id)} aria-label="关闭">
              ×
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  )
}

export function useToast() {
  const context = useContext(ToastContext)
  if (!context) throw new Error('useToast 必须在 ToastProvider 内部使用')
  return context
}
