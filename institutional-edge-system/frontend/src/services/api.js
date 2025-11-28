import axios from 'axios'
import { io } from 'socket.io-client'

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
  // Authentication
  async login(username, password) {
    const formData = new FormData();
    formData.append('username', username);
    formData.append('password', password);

    const response = await api.post('/api/auth/token', formData, {
      headers: { 'Content-Type': 'multipart/form-data' }
    });

    if (response.data.access_token) {
      localStorage.setItem('token', response.data.access_token);
      localStorage.setItem('user', JSON.stringify({
        id: response.data.user_id,
        username: response.data.username
      }));
    }
    return response.data;
  },

  async register(email, username, password) {
    const response = await api.post('/api/auth/register', {
      email,
      username,
      password
    });
    return response.data;
  },

  logout() {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    window.location.href = '/login';
  },

  // Health Check
  async getHealth() {
    const response = await api.get('/health')
    return response.data
  },

  // Symbols
  async getSymbols() {
    const response = await api.get('/api/symbols')
    return response.data
  },

  // Market Analysis
  async analyzeMarket(symbol, timeframe, symbolType = 'forex') {
    const encodedSymbol = encodeURIComponent(symbol)
    const response = await api.get(`/api/analysis/${encodedSymbol}/${timeframe}?symbol_type=${symbolType}`)
    return response.data
  },

  async getMarketHistory(symbol, timeframe, bars = 100, symbolType = 'forex') {
    const encodedSymbol = encodeURIComponent(symbol)
    const response = await api.get(`/api/market/history/${encodedSymbol}/${timeframe}?bars=${bars}&symbol_type=${symbolType}`)
    return response.data
  },

  // MT5 Operations
  async getAccountInfo() {
    const response = await api.get('/api/mt5/account')
    return response.data
  },

  async getCurrentPrice(symbol) {
    const encodedSymbol = encodeURIComponent(symbol)
    const response = await api.get(`/api/mt5/price/${encodedSymbol}`)
    return response.data
  },

  async getPositions(symbol = null) {
    const params = symbol ? { symbol } : {}
    const response = await api.get('/api/mt5/positions', { params })
    return response.data
  },

  // Bot Control
  async getBots() {
    const response = await api.get('/api/bots')
    return response.data
  },

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

  async getBotConfig(botConfigId) {
    const response = await api.get(`/api/bot-config/${botConfigId}`)
    return response.data
  },

  async updateBotConfig(botConfigId, configData) {
    const response = await api.put(`/api/bot-config/${botConfigId}`, configData)
    return response.data
  },

  // Signals
  async getSignals(symbol = null, limit = 50, executedOnly = false) {
    const params = { limit }
    if (symbol) params.symbol = symbol
    if (executedOnly) params.executed_only = executedOnly
    const response = await api.get('/api/signals', { params })
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

  async closeTrade(ticket) {
    const response = await api.post(`/api/trades/close/${ticket}`)
    return response.data
  },

  async moveToBE(ticket) {
    const response = await api.post(`/api/trades/be/${ticket}`)
    return response.data
  },

  async trailSL(ticket) {
    const response = await api.post(`/api/trades/trail/${ticket}`)
    return response.data
  },

  async clearSignals() {
    const response = await api.delete('/api/signals')
    return response.data
  },

  // Performance Stats
  async getPerformanceMetrics(days = 30) {
    const response = await api.get(`/api/stats/performance?days=${days}`)
    return response.data
  },

  async getTradeHistory(limit = 100, offset = 0, symbol = null) {
    const params = { limit, offset }
    if (symbol) params.symbol = symbol
    const response = await api.get('/api/stats/history', { params })
    return response.data
  },

  // Socket.IO connection
  socket: null,

  getSocket() {
    if (this.socket) {
      return this.socket
    }

    this.socket = io(API_BASE_URL, {
      transports: ['websocket', 'polling'],
      autoConnect: true
    })

    this.socket.on('connect', () => {
      console.log('Socket.IO Connected:', this.socket.id)
    })

    this.socket.on('disconnect', () => {
      console.log('Socket.IO Disconnected')
    })

    this.socket.on('connect_error', (error) => {
      console.error('Socket.IO Connection Error:', error)
    })

    return this.socket
  },

  // Deprecated: Alias for backward compatibility
  initSocket() {
    return this.getSocket()
  }
}
