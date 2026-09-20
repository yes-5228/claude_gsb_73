import http, { toParams } from './client.js'

export const listExceedances = (params) => http.get('/exceedances', { params: toParams(params) })
export const getExceedance = (id) => http.get(`/exceedances/${id}`)
export const annotateExceedance = (id, payload) => http.patch(`/exceedances/${id}`, payload)
export const batchAnnotate = (payload) => http.post('/exceedances/annotations', payload)
export const exceedanceSummary = (params) =>
  http.get('/exceedances/summary', { params: toParams(params) })
export const exceedanceOptions = () => http.get('/exceedances/options')
export const exportExceedancesUrl = (params) =>
  `/exceedances/export?${new URLSearchParams(toParams(params)).toString()}`
