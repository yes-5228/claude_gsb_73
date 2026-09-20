export function Loading({ text = '加载中...' }) {
  return (
    <div className="loading-block">
      <span className="spinner" />
      <span>{text}</span>
    </div>
  )
}

export function EmptyState({ text = '暂无数据', icon = '📭', action = null }) {
  return (
    <div className="empty">
      <span className="empty-icon">{icon}</span>
      <div>{text}</div>
      {action ? <div style={{ marginTop: 12 }}>{action}</div> : null}
    </div>
  )
}

export function ErrorState({ error, onRetry }) {
  return (
    <div className="empty">
      <span className="empty-icon">⚠️</span>
      <div>{error?.message || '请求失败'}</div>
      {onRetry ? (
        <button type="button" className="btn btn-sm" style={{ marginTop: 12 }} onClick={onRetry}>
          重新加载
        </button>
      ) : null}
    </div>
  )
}

export function Alert({ tone = 'info', children }) {
  return (
    <div className={`alert alert-${tone}`}>
      <span>{children}</span>
    </div>
  )
}
