import { PAGE_SIZE_OPTIONS } from '../../constants/index.js'

export default function Pagination({ page, pages, total, pageSize, onPageChange, onPageSizeChange }) {
  const safePages = Math.max(pages || 1, 1)
  return (
    <div className="pager">
      <div className="pager-info">
        共 <span className="strong">{total}</span> 条记录 · 第 {page}/{safePages} 页
      </div>
      <div className="pager-controls">
        <select
          className="select"
          value={pageSize}
          onChange={(event) => onPageSizeChange?.(Number(event.target.value))}
          aria-label="每页条数"
        >
          {PAGE_SIZE_OPTIONS.map((size) => (
            <option key={size} value={size}>
              每页 {size} 条
            </option>
          ))}
        </select>
        <button type="button" className="btn btn-sm" disabled={page <= 1} onClick={() => onPageChange(1)}>
          首页
        </button>
        <button
          type="button"
          className="btn btn-sm"
          disabled={page <= 1}
          onClick={() => onPageChange(page - 1)}
        >
          上一页
        </button>
        <button
          type="button"
          className="btn btn-sm"
          disabled={page >= safePages}
          onClick={() => onPageChange(page + 1)}
        >
          下一页
        </button>
        <button
          type="button"
          className="btn btn-sm"
          disabled={page >= safePages}
          onClick={() => onPageChange(safePages)}
        >
          末页
        </button>
      </div>
    </div>
  )
}
