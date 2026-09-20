import { useCallback, useEffect, useRef, useState } from 'react'

/** Fetch a single payload (options, detail, dashboard) with reload support. */
export function useAsyncData(loader, { immediate = true, initial = null } = {}) {
  const [data, setData] = useState(initial)
  const [loading, setLoading] = useState(immediate)
  const [error, setError] = useState(null)
  const mounted = useRef(true)

  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
    }
  }, [])

  const run = useCallback(
    async (...args) => {
      setLoading(true)
      setError(null)
      try {
        const payload = await loader(...args)
        if (mounted.current) setData(payload)
        return payload
      } catch (err) {
        if (mounted.current) setError(err)
        throw err
      } finally {
        if (mounted.current) setLoading(false)
      }
    },
    [loader]
  )

  useEffect(() => {
    if (immediate) run().catch(() => {})
  }, [immediate, run])

  return { data, loading, error, reload: run, setData }
}
