<template>
  <div class="p-6 space-y-6">
    <!-- Header -->
    <div class="flex justify-between items-center">
      <div>
        <h1 class="text-2xl font-bold text-white">Strategy Backtester</h1>
        <p class="text-gray-400">Test strategies with historical data before going live</p>
      </div>
      <div class="flex space-x-3">
        <button 
          @click="runBacktest" 
          :disabled="isRunning"
          class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium flex items-center transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <span v-if="isRunning" class="mr-2 animate-spin">⟳</span>
          {{ isRunning ? `Running (${progress}%)` : 'Run Backtest' }}
        </button>
      </div>
    </div>

    <!-- Progress Bar -->
    <div v-if="isRunning" class="w-full bg-gray-700 rounded-full h-2.5 mb-6">
      <div class="bg-blue-600 h-2.5 rounded-full transition-all duration-300" :style="{ width: progress + '%' }"></div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Configuration Panel -->
      <div class="lg:col-span-1 space-y-6">
        <div class="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <h2 class="text-lg font-semibold text-white mb-4">Configuration</h2>
          
          <div class="space-y-4">
            <!-- Symbol -->
            <div>
              <label class="block text-sm font-medium text-gray-400 mb-1">Symbol</label>
              <select v-model="config.symbol" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
                <option value="EURUSD">EURUSD</option>
                <option value="GBPUSD">GBPUSD</option>
                <option value="USDJPY">USDJPY</option>
                <option value="USDCAD">USDCAD</option>
                <option value="BTCUSD">BTCUSD</option>
                <option value="ETHUSD">ETHUSD</option>
              </select>
            </div>

            <!-- Timeframe -->
            <div>
              <label class="block text-sm font-medium text-gray-400 mb-1">Timeframe</label>
              <select v-model="config.timeframe" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
                <option value="M1">M1 (1 Minute)</option>
                <option value="M5">M5 (5 Minutes)</option>
                <option value="M15">M15 (15 Minutes)</option>
                <option value="H1">H1 (1 Hour)</option>
                <option value="H4">H4 (4 Hours)</option>
                <option value="D1">D1 (Daily)</option>
              </select>
            </div>

            <!-- Strategy Mode -->
            <div>
              <label class="block text-sm font-medium text-gray-400 mb-1">Strategy Mode</label>
              <div class="grid grid-cols-2 gap-2">
                <button 
                  @click="config.strategy_mode = 'SWING'"
                  :class="config.strategy_mode === 'SWING' ? 'bg-blue-600 border-blue-500 text-white' : 'bg-gray-900 border-gray-700 text-gray-400 hover:bg-gray-800'"
                  class="px-3 py-2 rounded-lg border text-sm font-medium transition-colors"
                >
                  Swing (H1+)
                </button>
                <button 
                  @click="config.strategy_mode = 'SCALP'"
                  :class="config.strategy_mode === 'SCALP' ? 'bg-purple-600 border-purple-500 text-white' : 'bg-gray-900 border-gray-700 text-gray-400 hover:bg-gray-800'"
                  class="px-3 py-2 rounded-lg border text-sm font-medium transition-colors"
                >
                  Scalp (M15)
                </button>
              </div>
            </div>

            <!-- Date Range -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-gray-400 mb-1">Start Date</label>
                <input type="date" v-model="config.start_date" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-400 mb-1">End Date</label>
                <input type="date" v-model="config.end_date" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
              </div>
            </div>

            <!-- Balance & Risk -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-gray-400 mb-1">Start Balance ($)</label>
                <input type="number" v-model.number="config.initial_balance" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-400 mb-1">Risk per Trade (%)</label>
                <input type="number" v-model.number="config.risk_percent" step="0.1" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
              </div>
            </div>
            
            <!-- Advanced Options -->
             <div class="pt-2 border-t border-gray-700">
                <label class="flex items-center space-x-2 cursor-pointer">
                  <input type="checkbox" v-model="config.use_adx_filter" class="form-checkbox h-4 w-4 text-blue-600 bg-gray-900 border-gray-700 rounded">
                  <span class="text-sm text-gray-300">Use ADX Filter (>25)</span>
                </label>
                <div v-if="config.strategy_mode === 'SCALP'" class="mt-2 space-y-2">
                    <label class="flex items-center space-x-2 cursor-pointer">
                        <input type="checkbox" v-model="config.enable_vwap_strategy" class="form-checkbox h-4 w-4 text-purple-600 bg-gray-900 border-gray-700 rounded">
                        <span class="text-sm text-gray-300">Enable VWAP Scalp</span>
                    </label>
                    <label class="flex items-center space-x-2 cursor-pointer">
                        <input type="checkbox" v-model="config.enable_stoch_strategy" class="form-checkbox h-4 w-4 text-purple-600 bg-gray-900 border-gray-700 rounded">
                        <span class="text-sm text-gray-300">Enable Stoch Momentum</span>
                    </label>
                    <label class="flex items-center space-x-2 cursor-pointer">
                        <input type="checkbox" v-model="config.enable_institutional_strategy" class="form-checkbox h-4 w-4 text-yellow-500 bg-gray-900 border-gray-700 rounded">
                        <span class="text-sm text-yellow-400 font-bold">Enable Institutional Sweep 💎</span>
                    </label>
                </div>
             </div>

          </div>
        </div>

        <!-- Recent History -->
        <div class="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <h2 class="text-lg font-semibold text-white mb-4">Recent Tests</h2>
          <div class="space-y-3">
            <div v-if="history.length === 0" class="text-center text-gray-500 py-4">
              No recent backtests
            </div>
            <div 
              v-for="session in history" 
              :key="session.id"
              @click="loadSession(session.id)"
              class="p-3 bg-gray-900 rounded-lg border border-gray-700 hover:border-blue-500 cursor-pointer transition-colors"
            >
              <div class="flex justify-between items-start mb-1">
                <span class="font-medium text-white">{{ session.symbol }}</span>
                <span 
                  class="text-xs px-2 py-0.5 rounded"
                  :class="session.net_profit >= 0 ? 'bg-green-900 text-green-400' : 'bg-red-900 text-red-400'"
                >
                  {{ session.net_profit >= 0 ? '+' : '' }}${{ session.net_profit?.toFixed(2) }}
                </span>
              </div>
              <div class="flex justify-between text-xs text-gray-400">
                <span>{{ session.timeframe }} • {{ session.total_trades }} Trades</span>
                <span>PF: {{ session.profit_factor?.toFixed(2) }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Results Dashboard -->
      <div class="lg:col-span-2 space-y-6">
        <!-- Key Metrics -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div class="bg-gray-800 p-4 rounded-xl border border-gray-700">
            <div class="text-sm text-gray-400 mb-1">Net Profit</div>
            <div class="text-2xl font-bold" :class="results.net_profit >= 0 ? 'text-green-400' : 'text-red-400'">
              {{ results.net_profit ? (results.net_profit >= 0 ? '+' : '') + '$' + results.net_profit.toFixed(2) : '-' }}
            </div>
          </div>
          <div class="bg-gray-800 p-4 rounded-xl border border-gray-700">
            <div class="text-sm text-gray-400 mb-1">Win Rate</div>
            <div class="text-2xl font-bold text-white">
              {{ results.win_rate ? results.win_rate.toFixed(1) + '%' : '-' }}
            </div>
          </div>
          <div class="bg-gray-800 p-4 rounded-xl border border-gray-700">
            <div class="text-sm text-gray-400 mb-1">Profit Factor</div>
            <div class="text-2xl font-bold" :class="getPfColor(results.profit_factor)">
              {{ results.profit_factor ? results.profit_factor.toFixed(2) : '-' }}
            </div>
          </div>
          <div class="bg-gray-800 p-4 rounded-xl border border-gray-700">
            <div class="text-sm text-gray-400 mb-1">Max Drawdown</div>
            <div class="text-2xl font-bold text-red-400">
              {{ results.max_drawdown ? results.max_drawdown.toFixed(1) + '%' : '-' }}
            </div>
          </div>
        </div>

        <!-- Equity Curve Placeholder (Future Implementation) -->
        <div class="bg-gray-800 rounded-xl border border-gray-700 p-5 h-64 flex items-center justify-center">
            <div class="text-center">
                <p class="text-gray-500">Equity Curve Chart</p>
                <p class="text-xs text-gray-600">(Coming Soon)</p>
            </div>
        </div>

        <!-- Trade List -->
        <div class="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
          <div class="p-4 border-b border-gray-700">
            <h3 class="font-semibold text-white">Trade History</h3>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="bg-gray-900 text-gray-400">
                <tr>
                  <th class="px-4 py-3">Time</th>
                  <th class="px-4 py-3">Type</th>
                  <th class="px-4 py-3">Price</th>
                  <th class="px-4 py-3">Profit</th>
                  <th class="px-4 py-3">Balance</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-700">
                <tr v-if="trades.length === 0">
                    <td colspan="5" class="px-4 py-8 text-center text-gray-500">No trades to display</td>
                </tr>
                <tr v-for="trade in trades" :key="trade.id" class="hover:bg-gray-750">
                  <td class="px-4 py-3 text-gray-300">{{ formatDate(trade.entry_time) }}</td>
                  <td class="px-4 py-3">
                    <span 
                      class="px-2 py-0.5 rounded text-xs font-medium"
                      :class="trade.trade_type === 'BUY' ? 'bg-green-900 text-green-400' : 'bg-red-900 text-red-400'"
                    >
                      {{ trade.trade_type }}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-gray-300">{{ trade.entry_price }}</td>
                  <td class="px-4 py-3 font-medium" :class="trade.profit >= 0 ? 'text-green-400' : 'text-red-400'">
                    {{ trade.profit >= 0 ? '+' : '' }}{{ trade.profit.toFixed(2) }}
                  </td>
                  <td class="px-4 py-3 text-gray-300">{{ trade.balance_after.toFixed(2) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import axios from 'axios'
import socket from '../services/socket'

// State
const isRunning = ref(false)
const progress = ref(0)
const history = ref([])
const trades = ref([])
const results = ref({})

// Config
const config = ref({
  symbol: 'EURUSD',
  timeframe: 'H1',
  strategy_mode: 'SWING',
  start_date: '2023-01-01',
  end_date: '2023-12-31',
  initial_balance: 1000,
  risk_percent: 1.0,
  use_adx_filter: true,
  enable_vwap_strategy: true,
  enable_stoch_strategy: true,
  enable_institutional_strategy: true
})

// Methods
const runBacktest = async () => {
  isRunning.value = true
  trades.value = []
  results.value = {}
  
  try {
    // Convert dates to ISO strings
    const payload = {
      ...config.value,
      start_date: new Date(config.value.start_date).toISOString(),
      end_date: new Date(config.value.end_date).toISOString()
    }
    
    const response = await axios.post('http://localhost:8000/api/backtest/run', payload)
    const sessionId = response.data.session_id
    
    // Connect socket if not connected
    if (!socket.connected) {
        socket.connect()
    }
    
  } catch (error) {
    console.error('Backtest failed:', error)
    alert('Failed to start backtest')
    isRunning.value = false
  }
}

// Socket Event Listeners
const setupSocketListeners = () => {
    socket.on('backtest_progress', (data) => {
        progress.value = Math.round(data.progress)
        
        // Update live stats if available
        if (data.stats) {
            results.value = {
                ...results.value,
                net_profit: data.stats.balance - config.value.initial_balance,
                total_trades: data.stats.trades,
                // Calculate other metrics roughly or wait for completion
            }
        }
    })

    socket.on('backtest_trade', (data) => {
        const trade = data.trade
        if (trade.type === 'CLOSE') {
            // Add to trades list
            trades.value.unshift({
                id: Date.now(), // Temp ID
                entry_time: trade.time,
                trade_type: trade.trade_type,
                entry_price: trade.price, // This is exit price in CLOSE event, need to adjust logic if we want full details
                // Wait, the event sends exit price as 'price'. 
                // We need entry price too for the table. 
                // The event payload in engine.py sends: type, symbol, trade_type, price (exit), entry_price, time, pnl, return_r, balance
                entry_price: trade.entry_price,
                exit_price: trade.price,
                profit: trade.pnl,
                balance_after: trade.balance
            })
            
            // Update balance in results
            results.value.net_profit = trade.balance - config.value.initial_balance
        }
    })

    socket.on('backtest_complete', (data) => {
        isRunning.value = false
        progress.value = 100
        results.value = data.results
        fetchHistory()
    })
}

const fetchHistory = async () => {
  try {
    const response = await axios.get('http://localhost:8000/api/backtest/history')
    history.value = response.data
  } catch (error) {
    console.error('Error fetching history:', error)
  }
}

const loadSession = async (sessionId) => {
  try {
    const response = await axios.get(`http://localhost:8000/api/backtest/${sessionId}`)
    results.value = response.data.session
    trades.value = response.data.trades
    // Update config to match loaded session (optional)
  } catch (error) {
    console.error('Error loading session:', error)
  }
}

const formatDate = (dateStr) => {
  return new Date(dateStr).toLocaleString()
}

const getPfColor = (pf) => {
  if (!pf) return 'text-gray-400'
  if (pf >= 1.5) return 'text-green-400'
  if (pf >= 1.0) return 'text-blue-400'
  return 'text-red-400'
}

// Init
onMounted(() => {
  fetchHistory()
  setupSocketListeners()
})

onUnmounted(() => {
    socket.off('backtest_progress')
    socket.off('backtest_trade')
    socket.off('backtest_complete')
})
</script>
