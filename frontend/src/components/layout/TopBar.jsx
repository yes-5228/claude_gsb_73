import { useCallback } from 'react'
import { health } from '../../api/meta.js'
import { useAsyncData } from '../../hooks/useAsyncData.js'

export default function TopBar({ item }) {
  const loader = useCallback(() => health(), [])
  const { data, error } = useAsyncData(loader)
  const online = !error && data?.status === 'ok'

  return (
    <header className="topbar">
      <div>
        <h1>{item?.title}</h1>
        <div className="topbar-sub">{item?.subtitle}</div>
      </div>
      <div className="topbar-meta">
        <span title={error ? error.message : `数据库: ${data?.database ?? '-'}`}>
          <span
            style={{
              display: 'inline-block',
              width: 8,
              height: 8,
              borderRadius: '50%',
              marginRight: 6,
              background: online ? 'var(--success)' : 'var(--danger)'
            }}
          />
          后端服务{online ? '正常' : '异常'}
        </span>
        <span>{data?.limit_policy ?? 'GB 3095-2012 二级标准'}</span>
        <span>{data?.timezone ?? 'Asia/Shanghai'}</span>
      </div>
    </header>
  )
}
