<template>
  <div class="min-h-screen bg-gradient-to-br from-slate-900 via-gray-900 to-slate-900 p-6">
    <div class="max-w-[1600px] mx-auto space-y-6">
      
      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <!-- HEADER                                                                   -->
      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <div class="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <div>
          <h1 class="text-2xl font-bold text-white flex items-center gap-2">
            📡 Trading Signals
            <span class="text-sm font-normal text-gray-400">XAU_PRO v4.0</span>
          </h1>
          <p class="text-gray-400 text-sm mt-1">Real-time signal scanner for manual trading</p>
        </div>
        
        <div class="flex items-center gap-3">
          <!-- Connection Status -->
          <div class="flex items-center gap-2 px-3 py-1.5 rounded-full text-xs"
               :class="socketConnected ? 'bg-green-500/10 text-green-400 border border-green-500/30' : 'bg-red-500/10 text-red-400 border border-red-500/30'">
            <span class="w-2 h-2 rounded-full" :class="socketConnected ? 'bg-green-400 animate-pulse' : 'bg-red-400'"></span>
            {{ socketConnected ? 'Live' : 'Offline' }}
          </div>
          
          <!-- Auto-Scan Toggle -->
          <label class="flex items-center gap-2 px-3 py-1.5 bg-slate-800 rounded-lg border border-slate-700 cursor-pointer">
            <input type="checkbox" v-model="autoScan" class="w-4 h-4 rounded bg-gray-700 border-gray-600 text-blue-500">
            <span class="text-sm text-gray-300">Auto-Scan</span>
          </label>
          
          <!-- Scan Button -->
          <button @click="scanSignals" 
                  :disabled="scanning"
                  class="px-5 py-2 bg-gradient-to-r from-blue-600 to-cyan-600 hover:from-blue-500 hover:to-cyan-500 text-white font-bold rounded-lg shadow-lg flex items-center gap-2 transition-all disabled:opacity-50">
            <span v-if="scanning" class="animate-spin">⟳</span>
            <span v-else>🔍</span>
            {{ scanning ? 'Scanning...' : 'Scan Now' }}
          </button>
        </div>
      </div>

      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <!-- FILTERS                                                                  -->
      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <div class="bg-slate-800/50 rounded-xl border border-slate-700/50 p-4">
        <div class="flex flex-wrap items-center gap-4">
          <!-- Symbol Selection -->
          <div class="flex items-center gap-2">
            <span class="text-xs text-gray-400 uppercase tracking-wider">Symbols:</span>
            <div class="flex flex-wrap gap-2">
              <button v-for="sym in availableSymbols" :key="sym.value"
                      @click="toggleSymbol(sym.value)"
                      class="px-3 py-1.5 rounded-lg text-sm font-medium transition-all"
                      :class="selectedSymbols.includes(sym.value)
                        ? 'bg-gradient-to-r from-blue-600 to-cyan-600 text-white shadow-lg'
                        : 'bg-slate-700 text-gray-400 hover:bg-slate-600 hover:text-white'">
                {{ sym.emoji }} {{ sym.value }}
              </button>
            </div>
          </div>
          
          <!-- Timeframe -->
          <div class="flex items-center gap-2 ml-auto">
            <span class="text-xs text-gray-400 uppercase tracking-wider">Timeframe:</span>
            <select v-model="selectedTimeframe" 
                    class="bg-slate-700 border border-slate-600 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="M5">M5</option>
              <option value="M15">M15</option>
              <option value="H1">H1</option>
              <option value="H4">H4</option>
            </select>
          </div>
        </div>
      </div>

      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <!-- ACTIVE SIGNALS                                                           -->
      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <div>
        <h2 class="text-lg font-bold text-white mb-4 flex items-center gap-2">
          ⚡ Active Signals
          <span v-if="signals.length" class="px-2 py-0.5 bg-blue-500/20 rounded-full text-xs text-blue-400">
            {{ signals.length }}
          </span>
        </h2>
        
        <!-- No Signals -->
        <div v-if="signals.length === 0 && !scanning" 
             class="bg-slate-800/30 rounded-xl border border-slate-700/30 p-12 text-center">
          <div class="text-6xl mb-4">📭</div>
          <p class="text-gray-400">No active signals found</p>
          <p class="text-sm text-gray-500 mt-2">Click "Scan Now" to search for entry opportunities</p>
        </div>
        
        <!-- Signal Cards Grid -->
        <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          <div v-for="signal in signals" :key="signal.timestamp" 
               class="bg-gradient-to-br from-slate-800 to-slate-900 rounded-xl border overflow-hidden transition-all hover:scale-[1.02] hover:shadow-xl"
               :class="signal.signal_type === 'BUY' 
                 ? 'border-green-500/30 hover:border-green-400/50' 
                 : 'border-red-500/30 hover:border-red-400/50'">
            
            <!-- Header -->
            <div class="p-4 border-b border-slate-700/50"
                 :class="signal.signal_type === 'BUY' ? 'bg-green-500/10' : 'bg-red-500/10'">
              <div class="flex justify-between items-center">
                <div class="flex items-center gap-2">
                  <span class="text-2xl">{{ getSymbolEmoji(signal.symbol) }}</span>
                  <div>
                    <div class="font-bold text-white">{{ signal.symbol }}</div>
                    <div class="text-xs text-gray-400">{{ signal.timeframe }}</div>
                  </div>
                </div>
                <span class="px-3 py-1 rounded-lg font-bold text-sm"
                      :class="signal.signal_type === 'BUY' 
                        ? 'bg-green-500/20 text-green-400 border border-green-500/30' 
                        : 'bg-red-500/20 text-red-400 border border-red-500/30'">
                  {{ signal.signal_type === 'BUY' ? '📈 BUY' : '📉 SELL' }}
                </span>
              </div>
            </div>
            
            <!-- Price Details -->
            <div class="p-4 space-y-3">
              <div class="grid grid-cols-2 gap-3 text-sm">
                <div class="bg-slate-800/50 rounded-lg p-2">
                  <div class="text-gray-500 text-xs">Entry</div>
                  <div class="font-mono font-bold text-white">{{ formatPrice(signal.price, signal.symbol) }}</div>
                </div>
                <div class="bg-slate-800/50 rounded-lg p-2">
                  <div class="text-gray-500 text-xs">Score</div>
                  <div class="font-bold" :class="signal.confluence_score >= 90 ? 'text-green-400' : 'text-yellow-400'">
                    {{ signal.confluence_score }}/100
                  </div>
                </div>
                <div class="bg-red-500/10 rounded-lg p-2 border border-red-500/20">
                  <div class="text-red-400 text-xs">Stop Loss</div>
                  <div class="font-mono font-bold text-red-300">{{ formatPrice(signal.stop_loss, signal.symbol) }}</div>
                </div>
                <div class="bg-green-500/10 rounded-lg p-2 border border-green-500/20">
                  <div class="text-green-400 text-xs">Take Profit</div>
                  <div class="font-mono font-bold text-green-300">{{ formatPrice(signal.take_profit_1, signal.symbol) }}</div>
                </div>
              </div>
              
              <!-- Metadata -->
              <div v-if="signal.metadata" class="flex flex-wrap gap-1">
                <span v-if="signal.metadata.in_order_block" class="px-2 py-0.5 bg-purple-500/20 text-purple-400 text-xs rounded border border-purple-500/30">OB</span>
                <span v-if="signal.metadata.liquidity_swept" class="px-2 py-0.5 bg-yellow-500/20 text-yellow-400 text-xs rounded border border-yellow-500/30">Sweep</span>
                <span v-if="signal.metadata.in_fvg" class="px-2 py-0.5 bg-blue-500/20 text-blue-400 text-xs rounded border border-blue-500/30">FVG</span>
                <span v-if="signal.metadata.fib_level" class="px-2 py-0.5 bg-cyan-500/20 text-cyan-400 text-xs rounded border border-cyan-500/30">Fib {{ signal.metadata.fib_level }}</span>
              </div>
              
              <!-- Time -->
              <div class="text-xs text-gray-500 flex items-center gap-1">
                <span>🕐</span>
                {{ formatTime(signal.timestamp) }}
              </div>
            </div>
            
            <!-- Actions -->
            <div class="p-3 border-t border-slate-700/50 flex gap-2">
              <button @click="copySignal(signal)"
                      class="flex-1 px-3 py-2 bg-slate-700 hover:bg-slate-600 text-gray-300 text-sm font-medium rounded-lg transition-colors flex items-center justify-center gap-1">
                📋 Copy
              </button>
              <button @click="executeSignal(signal)"
                      class="flex-1 px-3 py-2 font-bold text-sm rounded-lg transition-all flex items-center justify-center gap-1"
                      :class="signal.signal_type === 'BUY'
                        ? 'bg-gradient-to-r from-green-600 to-emerald-600 hover:from-green-500 hover:to-emerald-500 text-white'
                        : 'bg-gradient-to-r from-red-600 to-rose-600 hover:from-red-500 hover:to-rose-500 text-white'">
                ⚡ Trade
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <!-- SIGNAL HISTORY                                                           -->
      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <div class="bg-slate-800/50 rounded-xl border border-slate-700/50 overflow-hidden">
        <div class="px-4 py-3 border-b border-slate-700/50 flex justify-between items-center">
          <h3 class="font-bold text-white flex items-center gap-2">
            📜 Signal History
            <span class="text-xs text-gray-500">(Last {{ signalHistory.length }})</span>
          </h3>
          <button @click="clearHistory" class="text-xs text-gray-500 hover:text-red-400 transition-colors">
            Clear
          </button>
        </div>
        
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-slate-900/50 text-gray-500 text-xs uppercase">
              <tr>
                <th class="px-4 py-3 text-left">Time</th>
                <th class="px-4 py-3 text-left">Symbol</th>
                <th class="px-4 py-3 text-center">Type</th>
                <th class="px-4 py-3 text-right">Entry</th>
                <th class="px-4 py-3 text-right">SL</th>
                <th class="px-4 py-3 text-right">TP</th>
                <th class="px-4 py-3 text-center">Score</th>
                <th class="px-4 py-3 text-center">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-700/50">
              <tr v-if="signalHistory.length === 0">
                <td colspan="8" class="px-4 py-8 text-center text-gray-500">No history yet</td>
              </tr>
              <tr v-for="sig in signalHistory" :key="sig.timestamp" class="hover:bg-slate-800/30 transition-colors">
                <td class="px-4 py-3 text-gray-400">{{ formatTime(sig.timestamp) }}</td>
                <td class="px-4 py-3 font-medium text-white">{{ sig.symbol }}</td>
                <td class="px-4 py-3 text-center">
                  <span class="px-2 py-0.5 rounded text-xs font-bold"
                        :class="sig.signal_type === 'BUY' ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'">
                    {{ sig.signal_type }}
                  </span>
                </td>
                <td class="px-4 py-3 text-right font-mono text-gray-300">{{ formatPrice(sig.price, sig.symbol) }}</td>
                <td class="px-4 py-3 text-right font-mono text-red-400">{{ formatPrice(sig.stop_loss, sig.symbol) }}</td>
                <td class="px-4 py-3 text-right font-mono text-green-400">{{ formatPrice(sig.take_profit_1, sig.symbol) }}</td>
                <td class="px-4 py-3 text-center">
                  <span class="font-bold" :class="sig.confluence_score >= 90 ? 'text-green-400' : 'text-yellow-400'">
                    {{ sig.confluence_score }}
                  </span>
                </td>
                <td class="px-4 py-3 text-center">
                  <span class="px-2 py-0.5 rounded text-xs" 
                        :class="sig.executed ? 'bg-blue-500/20 text-blue-400' : 'bg-gray-500/20 text-gray-400'">
                    {{ sig.executed ? 'EXECUTED' : 'PENDING' }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <!-- TOAST NOTIFICATION                                                       -->
      <!-- ═══════════════════════════════════════════════════════════════════════ -->
      <transition name="slide-up">
        <div v-if="toast.show" 
             class="fixed bottom-6 right-6 px-4 py-3 rounded-xl shadow-xl border backdrop-blur-xl z-50"
             :class="{
               'bg-green-500/10 border-green-500/30 text-green-400': toast.type === 'success',
               'bg-red-500/10 border-red-500/30 text-red-400': toast.type === 'error',
               'bg-blue-500/10 border-blue-500/30 text-blue-400': toast.type === 'info'
             }">
          {{ toast.message }}
        </div>
      </transition>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import axios from 'axios'
import socket, { connectionState } from '@/services/socket'

// ============================================================================
// STATE
// ============================================================================

const signals = ref([])
const signalHistory = ref([])
const scanning = ref(false)
const autoScan = ref(false)
const selectedTimeframe = ref('M15')
const selectedSymbols = ref(['XAUUSD'])
const socketConnected = connectionState.isConnected

const toast = ref({ show: false, message: '', type: 'info' })

let autoScanInterval = null

const availableSymbols = [
  { value: 'XAUUSD', emoji: '🥇' },
  { value: 'EURUSD', emoji: '💶' },
  { value: 'GBPUSD', emoji: '💷' },
  { value: 'USDJPY', emoji: '💴' },
  { value: 'EURJPY', emoji: '🇪🇺🇯🇵' }
]

// ============================================================================
// METHODS
// ============================================================================

const toggleSymbol = (sym) => {
  if (selectedSymbols.value.includes(sym)) {
    selectedSymbols.value = selectedSymbols.value.filter(s => s !== sym)
  } else {
    selectedSymbols.value.push(sym)
  }
}

const scanSignals = async () => {
  if (selectedSymbols.value.length === 0) {
    showToast('Please select at least one symbol', 'error')
    return
  }
  
  scanning.value = true
  
  try {
    const response = await axios.get('/api/signals/scan', {
      params: {
        symbols: selectedSymbols.value.join(','),
        timeframe: selectedTimeframe.value
      }
    })
    
    const newSignals = response.data.signals || []
    
    // Add to active signals (replace existing)
    signals.value = newSignals
    
    // Add to history
    newSignals.forEach(sig => {
      signalHistory.value.unshift({ ...sig, executed: false })
    })
    
    // Keep history limited
    if (signalHistory.value.length > 50) {
      signalHistory.value = signalHistory.value.slice(0, 50)
    }
    
    if (newSignals.length > 0) {
      showToast(`Found ${newSignals.length} signal(s)!`, 'success')
      playNotificationSound()
    } else {
      showToast('No signals found', 'info')
    }
    
  } catch (error) {
    console.error('Scan failed:', error)
    showToast('Scan failed: ' + (error.response?.data?.detail || error.message), 'error')
  } finally {
    scanning.value = false
  }
}

const copySignal = (signal) => {
  const text = `${signal.signal_type} ${signal.symbol}
Entry: ${signal.price}
SL: ${signal.stop_loss}
TP: ${signal.take_profit_1}
Score: ${signal.confluence_score}/100
Strategy: ${signal.strategy}`
  
  navigator.clipboard.writeText(text)
  showToast('Signal copied to clipboard!', 'success')
}

const executeSignal = async (signal) => {
  // Mark as executed in history
  const historyItem = signalHistory.value.find(s => s.timestamp === signal.timestamp)
  if (historyItem) historyItem.executed = true
  
  // Open manual trade modal (emit event or call API)
  try {
    const response = await axios.post('/api/trading/manual-order', {
      symbol: signal.symbol,
      order_type: signal.signal_type,
      volume: 0.01, // Default lot size
      stop_loss: signal.stop_loss,
      take_profit: signal.take_profit_1
    })
    
    if (response.data.success) {
      showToast(`Trade executed! Ticket: ${response.data.ticket}`, 'success')
      // Remove from active signals
      signals.value = signals.value.filter(s => s.timestamp !== signal.timestamp)
    } else {
      showToast(`Trade failed: ${response.data.error}`, 'error')
    }
  } catch (error) {
    showToast(`Error: ${error.response?.data?.detail || error.message}`, 'error')
  }
}

const clearHistory = () => {
  signalHistory.value = []
}

const showToast = (message, type = 'info') => {
  toast.value = { show: true, message, type }
  setTimeout(() => { toast.value.show = false }, 3000)
}

const playNotificationSound = () => {
  // Optional: Add notification sound
  try {
    const audio = new Audio('data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2teleT8Etc/teleT8Etc/tele...')
    audio.volume = 0.3
    audio.play().catch(() => {})
  } catch (e) {}
}

// ============================================================================
// FORMATTERS
// ============================================================================

const formatPrice = (price, symbol) => {
  if (!price) return '-'
  const decimals = symbol?.includes('JPY') ? 3 : symbol?.includes('XAU') ? 2 : 5
  return price.toFixed(decimals)
}

const formatTime = (iso) => {
  if (!iso) return '-'
  return new Date(iso).toLocaleTimeString('en-US', { 
    hour12: false, 
    hour: '2-digit', 
    minute: '2-digit', 
    second: '2-digit' 
  })
}

const getSymbolEmoji = (symbol) => {
  const map = { 'XAUUSD': '🥇', 'EURUSD': '💶', 'GBPUSD': '💷', 'USDJPY': '💴', 'EURJPY': '🇪🇺🇯🇵' }
  return map[symbol] || '📊'
}

// ============================================================================
// WATCHERS
// ============================================================================

watch(autoScan, (enabled) => {
  if (enabled) {
    autoScanInterval = setInterval(scanSignals, 30000) // Every 30s
    showToast('Auto-scan enabled (every 30s)', 'info')
  } else {
    if (autoScanInterval) clearInterval(autoScanInterval)
    showToast('Auto-scan disabled', 'info')
  }
})

// ============================================================================
// LIFECYCLE
// ============================================================================

onMounted(() => {
  // Listen for real-time signals
  socket.on('signal_generated', (signal) => {
    // Add to active signals if matches our filters
    if (selectedSymbols.value.includes(signal.symbol)) {
      signals.value.unshift(signal)
      signalHistory.value.unshift({ ...signal, executed: false })
      showToast(`New signal: ${signal.signal_type} ${signal.symbol}`, 'success')
      playNotificationSound()
    }
  })
})

onUnmounted(() => {
  socket.off('signal_generated')
  if (autoScanInterval) clearInterval(autoScanInterval)
})
</script>

<style scoped>
.slide-up-enter-active,
.slide-up-leave-active {
  transition: all 0.3s ease-out;
}

.slide-up-enter-from,
.slide-up-leave-to {
  opacity: 0;
  transform: translateY(20px);
}
</style>
