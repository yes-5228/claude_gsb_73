import http from './client.js'

export const health = () => http.get('/meta/health')
export const pollutants = () => http.get('/meta/pollutants')
export const metaOptions = () => http.get('/meta/options')
export const overview = () => http.get('/meta/overview')
