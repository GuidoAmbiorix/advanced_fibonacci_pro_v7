<template>
  <div class="min-h-screen bg-slate-900 text-white font-sans p-6">
    <!-- Header -->
    <header class="flex justify-between items-center mb-8">
      <div>
        <h1 class="text-3xl font-black text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-emerald-400">
          SIGNALS DASHBOARD
        </h1>
        <p class="text-slate-400 mt-1">Real-time opportunities across all markets</p>
      </div>
      <div class="flex items-center space-x-4">
        <button 
          @click="fetchSignals" 
          class="px-4 py-2 bg-slate-800 hover:bg-slate-700 rounded-lg text-sm font-bold transition-colors flex items-center"
        >
          <span class="mr-2">🔄</span> Refresh
        </button>
        <router-link 
          to="/" 
          class="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg text-sm font-bold transition-colors"
        >
          Back to Terminal
        </router-link>
      </div>
    </header>

    <!-- Filters -->
    <div class="bg-slate-800/50 backdrop-blur-md border border-slate-700 rounded-xl p-4 mb-6 flex flex-wrap gap-4 items-center">
      <div class="flex items-center space-x-2">
        <span class="text-sm text-slate-400 font-bold">FILTER:</span>
        <select v-model="filterType" class="bg-slate-900 border border-slate-700 rounded px-3 py-1 text-sm focus:outline-none focus:border-blue-500">
          <option value="ALL">All Types</option>
          <option value="BUY">Buy Only</option>
          <option value="SELL">Sell Only</option>
        </select>
      </div>
      
      <div class="flex items-center space-x-2">
        <span class="text-sm text-slate-400 font-bold">MIN SCORE:</span>
        <select v-model="minScore" class="bg-slate-900 border border-slate-700 rounded px-3 py-1 text-sm focus:outline-none focus:border-blue-500">
          <option :value="0">All Scores</option>
          <option :value="6">6+</option>
          <option :value="7">7+</option>
          <option :value="8">8+</option>
          <option :value="9">9+</option>
        </select>
      </div>

      <div class="ml-auto text-sm text-slate-500">
        Showing {{ filteredSignals.length }} signals
      </div>
    </div>

    <!-- Signals Grid -->
    <div v-if="loading" class="flex justify-center py-20">
      <div class="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
    </div>

    <div v-else-if="filteredSignals.length === 0" class="text-center py-20 text-slate-500">
      <div class="text-6xl mb-4">📭</div>
      <p class="text-xl">No signals found matching your criteria.</p>
    </div>

    <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      <div 
        v-for="signal in filteredSignals" 
        :key="signal.id"
        class="bg-slate-800/50 backdrop-blur-md border rounded-xl p-5 hover:shadow-lg transition-all duration-300 group relative overflow-hidden"
        :class="signal.signal_type === 'BUY' ? 'border-emerald-500/30 hover:border-emerald-500/60' : 'border-red-500/30 hover:border-red-500/60'"
      >
        <!-- Background Gradient -->
        <div 
          class="absolute inset-0 opacity-0 group-hover:opacity-10 transition-opacity duration-500 pointer-events-none"
          :class="signal.signal_type === 'BUY' ? 'bg-emerald-500' : 'bg-red-500'"
        ></div>

        <!-- Header -->
        <div class="flex justify-between items-start mb-4 relative z-10">
          <div>
            <div class="flex items-center space-x-2">
              <span class="text-2xl font-black tracking-tight">{{ signal.symbol }}</span>
              <span class="text-xs font-mono bg-slate-900 px-2 py-0.5 rounded text-slate-400">{{ signal.timeframe }}</span>
            </div>
            <div class="text-xs text-slate-500 mt-1">{{ formatTimeAgo(signal.created_at) }}</div>
          </div>
          <div 
            class="px-3 py-1 rounded font-black text-sm tracking-wider"
            :class="signal.signal_type === 'BUY' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-red-500/20 text-red-400'"
          >
            {{ signal.signal_type }}
          </div>
        </div>

        <!-- Price & Score -->
        <div class="grid grid-cols-2 gap-4 mb-4 relative z-10">
          <div class="bg-slate-900/50 p-3 rounded-lg">
            <div class="text-xs text-slate-500 mb-1">Entry Price</div>
            <div class="font-mono font-bold text-lg">{{ formatPrice(signal.price) }}</div>
          </div>
          <div class="bg-slate-900/50 p-3 rounded-lg">
            <div class="text-xs text-slate-500 mb-1">Confluence</div>
            <div class="font-mono font-bold text-lg flex items-center">
              <span :class="getScoreColor(signal.confluence_score)">{{ signal.confluence_score }}/10</span>
            </div>
          </div>
        </div>

        <!-- AI Confidence -->
        <div v-if="signal.ai_confidence > 0" class="mb-4 relative z-10">
          <div class="flex justify-between text-xs mb-1">
            <span class="text-slate-400">AI Confidence</span>
            <span :class="getAIConfidenceColor(signal.ai_confidence)">{{ signal.ai_confidence.toFixed(1) }}%</span>
          </div>
          <div class="h-1.5 bg-slate-700 rounded-full overflow-hidden">
            <div 
              class="h-full rounded-full"
              :class="getAIConfidenceColor(signal.ai_confidence, true)"
              :style="`width: ${signal.ai_confidence}%`"
            ></div>
          </div>
        </div>

        <!-- Breakdown -->
        <div class="space-y-1 mb-5 relative z-10">
          <div v-for="(score, factor) in getTopFactors(signal.score_breakdown)" :key="factor" class="flex justify-between text-xs">
            <span class="text-slate-400">{{ factor }}</span>
            <span class="text-slate-300 font-bold">+{{ score }}</span>
          </div>
        </div>

        <!-- Action -->
        <button 
          @click="executeSignal(signal)"
          class="w-full py-3 rounded-lg font-bold text-sm uppercase tracking-wider transition-all duration-300 relative z-10 flex justify-center items-center space-x-2"
          :class="signal.signal_type === 'BUY' 
            ? 'bg-emerald-600 hover:bg-emerald-500 text-white shadow-lg shadow-emerald-900/20' 
            : 'bg-red-600 hover:bg-red-500 text-white shadow-lg shadow-red-900/20'"
        >
          <span>Execute Trade</span>
          <span>⚡</span>
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import api from '../services/api'

const signals = ref([])
const loading = ref(true)
const filterType = ref('ALL')
const minScore = ref(0)
let refreshInterval = null

// Computed
const filteredSignals = computed(() => {
  return signals.value.filter(s => {
    if (filterType.value !== 'ALL' && s.signal_type !== filterType.value) return false
    if (s.confluence_score < minScore.value) return false
    return true
  })
})

// Methods
async function fetchSignals() {
  loading.value = true
  try {
    // Fetch signals for ALL symbols (no symbol param)
    const data = await api.getSignals(null, 100)
    if (data && data.signals) {
      signals.value = data.signals
    }
  } catch (e) {
    console.error("Failed to fetch signals", e)
  } finally {
    loading.value = false
  }
}

async function executeSignal(signal) {
  if (!confirm(`Execute ${signal.signal_type} on ${signal.symbol}?`)) return

  try {
    const tradeData = {
      symbol: signal.symbol,
      trade_type: signal.signal_type,
      volume: 0.01, // Default lot size
      stop_loss: signal.stop_loss,
      take_profit_1: signal.take_profit,
      take_profit_2: null,
      take_profit_3: null,
      risk_percent: 1.0,
      confluence_score: signal.confluence_score,
      score_breakdown: signal.score_breakdown
    }

    const result = await api.openTrade(tradeData)
    if (result.success) {
      alert(`Trade executed successfully! Ticket: ${result.ticket}`)
    }
  } catch (e) {
    console.error("Trade execution failed", e)
    alert("Failed to execute trade. Check console for details.")
  }
}

// Helpers
const formatPrice = (price) => {
  return new Intl.NumberFormat('en-US', { 
    minimumFractionDigits: 2, 
    maximumFractionDigits: 5 
  }).format(price)
}

const formatTimeAgo = (isoTimestamp) => {
  if (!isoTimestamp) return 'never'
  const date = new Date(isoTimestamp)
  const seconds = Math.floor((new Date() - date) / 1000)
  
  if (seconds < 60) return `${seconds}s ago`
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
  return `${Math.floor(seconds / 86400)}d ago`
}

const getScoreColor = (score) => {
  if (score >= 8) return 'text-emerald-400'
  if (score >= 6) return 'text-yellow-400'
  return 'text-red-400'
}

const getAIConfidenceColor = (confidence, isBg = false) => {
  if (confidence >= 75) return isBg ? 'bg-emerald-500' : 'text-emerald-400'
  if (confidence >= 60) return isBg ? 'bg-blue-500' : 'text-blue-400'
  if (confidence >= 45) return isBg ? 'bg-yellow-500' : 'text-yellow-400'
  return isBg ? 'bg-red-500' : 'text-red-400'
}

const getTopFactors = (breakdown) => {
  if (!breakdown) return {}
  // Return top 3 factors
  return Object.entries(breakdown)
    .sort(([,a], [,b]) => b - a)
    .slice(0, 3)
    .reduce((r, [k, v]) => ({ ...r, [k]: v }), {})
}

// Lifecycle
onMounted(() => {
  fetchSignals()
  // Auto-refresh every 30 seconds
  refreshInterval = setInterval(fetchSignals, 30000)
})

onUnmounted(() => {
  if (refreshInterval) clearInterval(refreshInterval)
})
</script>
