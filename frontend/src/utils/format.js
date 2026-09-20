/** Formatting helpers that keep local (server) wall-clock time intact. */

export function formatDateTime(value, fallback = '-') {
  if (!value) return fallback
  return String(value).replace('T', ' ').slice(0, 16)
}

export function formatDate(value, fallback = '-') {
  if (!value) return fallback
  return String(value).slice(0, 10)
}

export function formatNumber(value, precision = 2) {
  if (value === null || value === undefined || value === '') return '-'
  const number = Number(value)
  if (Number.isNaN(number)) return '-'
  const fixed = number.toFixed(precision)
  return fixed.includes('.') ? fixed.replace(/0+$/, '').replace(/\.$/, '') : fixed
}

export function formatRatio(ratio) {
  if (ratio === null || ratio === undefined) return '-'
  return `${Number(ratio).toFixed(2)} 倍`
}

export function formatPercent(rate, digits = 1) {
  if (rate === null || rate === undefined) return '-'
  return `${(Number(rate) * 100).toFixed(digits)}%`
}

/** yyyy-MM-ddTHH:mm for <input type="datetime-local"> */
export function toDateTimeInput(date = new Date()) {
  const pad = (value) => String(value).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}
