export function SectionCard({ title, hint, actions, children, tight = false, footer }) {
  return (
    <div className="card">
      {title ? (
        <div className="card-header">
          <div>
            <h3>{title}</h3>
            {hint ? <div className="hint">{hint}</div> : null}
          </div>
          {actions ? <div className="inline">{actions}</div> : null}
        </div>
      ) : null}
      <div className={tight ? 'card-body tight' : 'card-body'}>{children}</div>
      {footer ? <div className="table-caption">{footer}</div> : null}
    </div>
  )
}

export function FilterPanel({ children, onSearch, onReset, loading = false, extra }) {
  return (
    <div className="card">
      <div className="card-body">
        <div className="filter-bar">
          {children}
          <div className="filter-actions">
            <button type="button" className="btn btn-primary" onClick={onSearch} disabled={loading}>
              {loading ? '查询中...' : '查询'}
            </button>
            {onReset ? (
              <button type="button" className="btn" onClick={onReset} disabled={loading}>
                重置
              </button>
            ) : null}
          </div>
        </div>
        {extra ? <div style={{ marginTop: 12 }}>{extra}</div> : null}
      </div>
    </div>
  )
}
