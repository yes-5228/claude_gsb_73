import http, { toParams } from './client.js'

export const listStations = (params) => http.get('/stations', { params: toParams(params) })
export const getStation = (id) => http.get(`/stations/${id}`)
export const createStation = (payload) => http.post('/stations', payload)
export const updateStation = (id, payload) => http.put(`/stations/${id}`, payload)
export const deleteStation = (id) => http.delete(`/stations/${id}`)
export const stationOptions = () => http.get('/stations/options')
export const stationSummary = () => http.get('/stations/summary')
