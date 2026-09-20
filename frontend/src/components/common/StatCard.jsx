export default function StatCard({ label, value, unit, foot, tone }) {
  const color = tone === 'danger' ? 'var(--danger)' : tone === 'warning' ? 'var(--warning)' : 'var(--text)'
  return (
    <div className="stat-card">
      <div className="stat-label">{label}</div>
      <div className="stat-value" style={{ color }}>
        {value}
        {unit ? <small>{unit}</small> : null}
      </div>
      {foot ? <div className="stat-foot">{foot}</div> : null}
    </div>
  )
}
