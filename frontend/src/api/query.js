import http, { toParams } from './client.js'

export const queryMeasurements = (params) => http.get('/query/measurements', { params: toParams(params) })
export const queryStatistics = (params) => http.get('/query/statistics', { params: toParams(params) })
export const queryOptions = () => http.get('/query/options')
export const exportQueryUrl = (params) =>
  `/query/export?${new URLSearchParams(toParams(params)).toString()}`
