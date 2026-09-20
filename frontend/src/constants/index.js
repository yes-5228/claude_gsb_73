export const NAV_ITEMS = [
  { to: '/overview', label: '运行概览', icon: '📊', title: '运行概览', subtitle: '监测点规模、数据量与超标待办一览' },
  { to: '/stations', label: '监测点台账', icon: '📍', title: '监测点台账', subtitle: '维护监测点档案、点位信息与运行状态' },
  { to: '/measurements', label: '监测数据录入', icon: '✍️', title: '监测数据录入', subtitle: '按“监测点 + 时刻”成组录入各因子浓度' },
  { to: '/exceedances', label: '超标记录标注', icon: '⚠️', title: '超标记录标注', subtitle: '复核超标记录, 标注确认或忽略原因' },
  { to: '/query', label: '数据查询', icon: '🔍', title: '数据查询', subtitle: '多条件检索、聚合统计与结果导出' }
]

export const PAGE_SIZE_OPTIONS = [10, 20, 50, 100]

export const STATION_STATUS_TONE = { active: 'success', maintenance: 'warning', offline: 'neutral' }
export const EXCEEDANCE_STATUS_TONE = { pending: 'warning', confirmed: 'danger', ignored: 'neutral' }
export const EXCEEDANCE_LEVEL_TONE = { light: 'info', moderate: 'warning', severe: 'danger' }
export const DATA_SOURCE_TONE = { manual: 'primary', device: 'info', import: 'neutral' }

export const EXCEEDANCE_LEVEL_LABELS = { light: '轻度超标', moderate: '中度超标', severe: '重度超标' }
export const EXCEEDANCE_STATUS_LABELS = { pending: '待标注', confirmed: '已确认', ignored: '已忽略' }

export const POLLUTANT_CODE_LABELS = {
  PM25: 'PM2.5',
  PM10: 'PM10',
  SO2: 'SO₂',
  NO2: 'NO₂',
  CO: 'CO',
  O3: 'O₃'
}

export const REFRESH_HINT = '数据来自 Flask 后端 /api 接口'
