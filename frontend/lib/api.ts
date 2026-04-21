import axios from 'axios'

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001/api'

const api = axios.create({
    baseURL: API_BASE,
    timeout: 10000,
})

// Credit endpoints
export const getCreditProfile = (address: string) =>
    api.get(`/credit/${address}`).then(r => r.data)

export const canUserWrite = (address: string) =>
    api.get(`/credit/${address}/can-write`).then(r => r.data)

// Pool endpoints
export const getPoolStats = () =>
    api.get('/pool/stats').then(r => r.data)

export const getLenderStats = (address: string) =>
    api.get(`/pool/lender/${address}`).then(r => r.data)

export const getBorrowerStats = (address: string) =>
    api.get(`/pool/borrower/${address}`).then(r => r.data)

// Options endpoints
export const getOption = (optionId: number) =>
    api.get(`/options/${optionId}`).then(r => r.data)

export const getUserWrittenOptions = (address: string) =>
    api.get(`/options/user/${address}/written`).then(r => r.data)

export const getUserBoughtOptions = (address: string) =>
    api.get(`/options/user/${address}/bought`).then(r => r.data)

// Dashboard
export const getDashboardData = (address: string) =>
    api.get(`/user/${address}/dashboard`).then(r => r.data)

export default api