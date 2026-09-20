import StatCard from '../../../components/common/StatCard.jsx'
import { EXCEEDANCE_LEVEL_LABELS } from '../../../constants/index.js'
import { formatRatio } from '../../../utils/format.js'

export default function ExceedanceSummaryCards({ summary }) {
  if (!summary) {
    return (
      <div className="stat-grid">
        <StatCard label="超标记录" value="-" />
      </div>
    )
  }

  const byLevel = Object.fromEntries((summary.by_level || []).map((item) => [item.key, item.count]))
  const statusMap = Object.fromEntries((summary.by_status || []).map((item) => [item.key, item.count]))
  const topPollutants = (summary.top_pollutants || [])
    .slice(0, 3)
    .map((item) => `${item.key} ${item.count}`)
    .join(' · ')

  return (
    <div className="stat-grid">
      <StatCard label="筛选范围内超标记录" value={summary.total} foot={`最大超标倍数 ${formatRatio(summary.max_ratio)}`} />
      <StatCard
        label="待标注"
        value={summary.pending}
        tone={summary.pending ? 'warning' : undefined}
        foot={`已确认 ${statusMap.confirmed || 0} · 已忽略 ${statusMap.ignored || 0}`}
      />
      <StatCard
        label="等级分布"
        value={byLevel.severe || 0}
        unit="条重度"
        tone={byLevel.severe ? 'danger' : undefined}
        foot={Object.entries(EXCEEDANCE_LEVEL_LABELS)
          .map(([key, label]) => `${label} ${byLevel[key] || 0}`)
          .join(' · ')}
      />
      <StatCard label="平均超标倍数" value={formatRatio(summary.avg_ratio)} foot={topPollutants ? `高发因子: ${topPollutants}` : '暂无统计'} />
    </div>
  )
}
