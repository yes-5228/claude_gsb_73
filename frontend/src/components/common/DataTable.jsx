import { EmptyState, Loading } from './Feedback.jsx'

/**
 * Generic table: columns = [{ key, title, width, align, className, render(row) }]
 * Supports optional row selection, used by the exceedance work bench.
 */
export default function DataTable({
  columns,
  rows = [],
  rowKey = 'id',
  loading = false,
  emptyText = '暂无数据',
  emptyIcon = '📭',
  selectable = false,
  selectedIds = [],
  onToggleRow,
  onToggleAll,
  onRowClick,
  rowClassName,
  caption
}) {
  if (loading && rows.length === 0) return <Loading />

  const keys = rows.map((row) => row[rowKey])
  const allSelected = selectable && keys.length > 0 && keys.every((key) => selectedIds.includes(key))

  return (
    <>
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              {selectable ? (
                <th style={{ width: 44 }}>
                  <input
                    type="checkbox"
                    checked={allSelected}
                    onChange={() => onToggleAll?.(keys)}
                    aria-label="全选"
                  />
                </th>
              ) : null}
              {columns.map((column) => (
                <th key={column.key} style={column.width ? { width: column.width } : undefined}
                    className={column.align === 'right' ? 'text-right' : ''}>
                  {column.title}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => {
              const key = row[rowKey]
              const selected = selectedIds.includes(key)
              return (
                <tr
                  key={key}
                  className={`${onRowClick ? 'clickable' : ''} ${selected ? 'selected' : ''} ${
                    rowClassName ? rowClassName(row) : ''
                  }`}
                  onClick={onRowClick ? () => onRowClick(row) : undefined}
                >
                  {selectable ? (
                    <td onClick={(event) => event.stopPropagation()}>
                      <input
                        type="checkbox"
                        checked={selected}
                        onChange={() => onToggleRow?.(key)}
                        aria-label={`选择 ${key}`}
                      />
                    </td>
                  ) : null}
                  {columns.map((column) => (
                    <td
                      key={column.key}
                      className={`${column.align === 'right' ? 'text-right' : ''} ${
                        column.className || ''
                      }`}
                    >
                      {column.render ? column.render(row) : row[column.key] ?? '-'}
                    </td>
                  ))}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      {rows.length === 0 ? <EmptyState text={emptyText} icon={emptyIcon} /> : null}
      {caption ? <div className="table-caption">{caption}</div> : null}
    </>
  )
}
