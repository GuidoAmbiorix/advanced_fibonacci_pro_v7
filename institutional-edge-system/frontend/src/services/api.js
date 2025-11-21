import axios from 'axios'

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000'

const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  }
})

// Request interceptor for adding auth token
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('token')
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

// Response interceptor for error handling
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token')
      window.location.href = '/login'
    }
    return Promise.reject(error)
  }
)

export default {
  // Health Check
  async getHealth() {
    const response = await api.get('/health')
    return response.data
  },

  // Market Analysis
  async analyzeMarket(symbol, timeframe) {
    const response = await api.get(`/api/analysis/${symbol}/${timeframe}`)
    return response.data
  },

  // MT5 Operations
  async getAccountInfo() {
    const response = await api.get('/api/mt5/account')
    return response.data
  },

  async getCurrentPrice(symbol) {
    const response = await api.get(`/api/mt5/price/${symbol}`)
    return response.data
  },

  async getPositions(symbol = null) {
    const params = symbol ? { symbol } : {}
    const response = await api.get('/api/mt5/positions', { params })
    return response.data
  },

  // Bot Control
  async startBot(botConfigId) {
    const response = await api.post('/api/bot/start', { bot_config_id: botConfigId })
    return response.data
  },

  async stopBot(botConfigId) {
    const response = await api.post('/api/bot/stop', { bot_config_id: botConfigId })
    return response.data
  },

  async getBotStatus(botConfigId) {
    const response = await api.get(`/api/bot/status/${botConfigId}`)
    return response.data
  },

  // Trades
  async getTrades(limit = 50, status = null) {
    const params = { limit }
    if (status) params.status = status
    const response = await api.get('/api/trades', { params })
    return response.data
  },

  async openTrade(tradeData) {
    const response = await api.post('/api/trades/open', tradeData)
    return response.data
  },

  // WebSocket connection
  createWebSocket(onMessage, onError) {
    const wsUrl = API_BASE_URL.replace('http', 'ws') + '/ws'
    const ws = new WebSocket(wsUrl)

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data)
      onMessage(data)
    }

    ws.onerror = (error) => {
      console.error('WebSocket error:', error)
      if (onError) onError(error)
    }

    ws.onclose = () => {
      console.log('WebSocket connection closed')
      // Auto-reconnect after 5 seconds
      setTimeout(() => {
        this.createWebSocket(onMessage, onError)
      }, 5000)
    }

    return ws
  }
}
