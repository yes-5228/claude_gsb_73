import { formatNumber } from '../../utils/format.js'

/** Lightweight CSS bar chart used by the dashboard and statistics panel. */
export default function BarChart({ items = [], danger = false, precision = 1 }) {
  if (items.length === 0) return <div className="empty">暂无统计数据</div>
  const max = Math.max(...items.map((item) => Number(item.value) || 0), 1)

  return (
    <div className="bar-chart">
      {items.map((item) => {
        const height = Math.max(((Number(item.value) || 0) / max) * 100, 2)
        const hot = danger || item.exceeded_count > 0
        return (
          <div className="bar-item" key={item.key ?? item.label}>
            <div className="bar-value">{formatNumber(item.value, precision)}</div>
            <div className="bar-track">
              <div className={`bar-fill ${hot ? 'danger' : ''}`} style={{ height: `${height}%` }} title={`${item.label}: ${item.value}`} />
            </div>
            <div className="bar-label" title={item.label}>
              {item.label}
            </div>
          </div>
        )
      })}
    </div>
  )
}
