import { useCallback, useEffect, useRef, useState } from 'react'

/**
 * Shared list state for the four modules: filters + pagination + request lifecycle.
 * `fetcher` receives { ...filters, page, page_size } and must return the API payload.
 */
export function useListQuery(fetcher, initialFilters = {}, { pageSize = 20, enabled = true } = {}) {
  const [filters, setFilters] = useState(initialFilters)
  const [page, setPage] = useState(1)
  const [size, setSize] = useState(pageSize)
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(enabled)
  const [error, setError] = useState(null)
  const requestId = useRef(0)

  const load = useCallback(async () => {
    const current = ++requestId.current
    setLoading(true)
    setError(null)
    try {
      const payload = await fetcher({ ...filters, page, page_size: size })
      if (current === requestId.current) setData(payload)
    } catch (err) {
      if (current === requestId.current) {
        setError(err)
        setData(null)
      }
    } finally {
      if (current === requestId.current) setLoading(false)
    }
  }, [fetcher, filters, page, size])

  useEffect(() => {
    if (enabled) load()
  }, [enabled, load])

  const applyFilters = useCallback((next) => {
    setPage(1)
    setFilters(typeof next === 'function' ? next : next)
  }, [])

  return {
    items: data?.items ?? [],
    data,
    total: data?.total ?? 0,
    pages: data?.pages ?? 0,
    summary: data?.summary ?? null,
    filters,
    setFilters: applyFilters,
    page,
    setPage,
    pageSize: size,
    setPageSize: setSize,
    loading,
    error,
    reload: load
  }
}
