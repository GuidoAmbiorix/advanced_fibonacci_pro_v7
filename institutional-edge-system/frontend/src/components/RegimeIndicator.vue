<template>
  <div class="regime-indicator bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-6 shadow-2xl">
    <!-- Header -->
    <div class="flex items-center justify-between mb-4">
      <h3 class="text-sm font-bold text-white uppercase tracking-wider">Market Regime</h3>
      <button 
        @click="refresh"
        :disabled="loading"
        class="w-7 h-7 rounded-lg bg-gray-700/50 hover:bg-gray-600/50 flex items-center justify-center text-gray-400 hover:text-white transition-colors disabled:opacity-50"
      >
        <span :class="{ 'animate-spin': loading }">↻</span>
      </button>
    </div>

    <!-- Main Regime Display -->
    <div 
      class="relative overflow-hidden rounded-xl p-5 mb-4 transition-all duration-500"
      :class="regimeBackgroundClass"
    >
      <!-- Animated Background -->
      <div 
        v-if="isAnimated"
        class="absolute inset-0 opacity-30"
        :class="regimeAnimationClass"
      ></div>
      
      <!-- Content -->
      <div class="relative z-10">
        <div class="flex items-center gap-3 mb-2">
          <span class="text-3xl">{{ regimeIcon }}</span>
          <div>
            <div class="text-xl font-bold text-white">{{ regimeLabel }}</div>
            <div class="text-sm text-white/70">
              Confidence: {{ data?.regime_confidence?.toFixed(0) || 0 }}%
            </div>
          </div>
        </div>
        
        <!-- Confidence Bar -->
        <div class="mt-3 h-2 bg-black/30 rounded-full overflow-hidden">
          <div 
            class="h-full rounded-full transition-all duration-700"
            :class="confidenceBarClass"
            :style="{ width: `${data?.regime_confidence || 0}%` }"
          ></div>
        </div>
      </div>
    </div>

    <!-- Metrics Grid -->
    <div class="grid grid-cols-2 gap-3 mb-4">
      <!-- Volatility -->
      <div class="p-3 rounded-xl bg-gray-800/50 border border-gray-700/50">
        <div class="text-xs text-gray-400 mb-1">Volatility</div>
        <div class="flex items-center gap-2">
          <span class="text-lg">{{ volatilityIcon }}</span>
          <span 
            class="text-sm font-bold"
            :class="volatilityTextClass"
          >
            {{ data?.volatility || 'NORMAL' }}
          </span>
        </div>
        <div class="text-xs text-gray-500 mt-1">
          {{ data?.volatility_percentile?.toFixed(0) || 50 }}th percentile
        </div>
      </div>

      <!-- Trend Strength -->
      <div class="p-3 rounded-xl bg-gray-800/50 border border-gray-700/50">
        <div class="text-xs text-gray-400 mb-1">Trend Strength</div>
        <div class="flex items-center gap-2">
          <!-- Trend Bars -->
          <div class="flex gap-0.5">
            <div 
              v-for="i in 5" 
              :key="i"
              class="w-2 h-4 rounded-sm transition-colors"
              :class="getTrendBarClass(i)"
            ></div>
          </div>
          <span class="text-sm text-gray-300">
            {{ getTrendLabel }}
          </span>
        </div>
      </div>
    </div>

    <!-- Hurst Exponent -->
    <div class="p-3 rounded-xl bg-gray-800/50 border border-gray-700/50 mb-4">
      <div class="flex items-center justify-between">
        <div>
          <div class="text-xs text-gray-400 mb-1">Hurst Exponent</div>
          <div class="text-lg font-mono font-bold" :class="hurstTextClass">
            {{ data?.hurst_exponent?.toFixed(3) || 'N/A' }}
          </div>
        </div>
        <div class="text-right">
          <div class="text-xs text-gray-400 mb-1">Interpretation</div>
          <div class="text-sm font-medium" :class="hurstTextClass">
            {{ hurstInterpretation }}
          </div>
        </div>
      </div>
      
      <!-- Hurst Scale -->
      <div class="mt-3">
        <div class="flex justify-between text-[10px] text-gray-500 mb-1">
          <span>Mean-Reverting</span>
          <span>Random</span>
          <span>Trending</span>
        </div>
        <div class="h-2 rounded-full bg-gradient-to-r from-blue-500 via-gray-500 to-orange-500 relative">
          <!-- Marker -->
          <div 
            v-if="data?.hurst_exponent"
            class="absolute top-1/2 -translate-y-1/2 w-3 h-3 bg-white rounded-full border-2 border-gray-900 shadow-lg transition-all duration-500"
            :style="{ left: `${data.hurst_exponent * 100}%`, transform: 'translate(-50%, -50%)' }"
          ></div>
        </div>
      </div>
    </div>

    <!-- Recommendation -->
    <div class="p-4 rounded-xl bg-gradient-to-r from-purple-500/10 to-pink-500/10 border border-purple-500/20">
      <div class="flex items-start gap-3">
        <span class="text-xl">💡</span>
        <div>
          <div class="text-xs font-medium text-purple-400 uppercase tracking-wider mb-1">Trading Tip</div>
          <p class="text-sm text-gray-300 leading-relaxed">
            {{ data?.recommendation || 'Analyzing market conditions...' }}
          </p>
        </div>
      </div>
    </div>

    <!-- Duration -->
    <div v-if="data?.regime_duration_bars" class="mt-4 text-center text-xs text-gray-500">
      Current regime: {{ data.regime_duration_bars }} bars
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import api from '../services/api'

// Props
const props = defineProps({
  symbol: { type: String, default: 'EURUSD' },
  timeframe: { type: String, default: 'H1' },
  autoRefresh: { type: Boolean, default: true },
  refreshInterval: { type: Number, default: 60000 } // 1 minute
})

// Emits
const emit = defineEmits(['regime-change'])

// State
const data = ref(null)
const loading = ref(false)
const previousRegime = ref(null)
let refreshTimer = null

// Computed
const regimeIcon = computed(() => {
  const icons = {
    'TRENDING_BULL': '🔥',
    'TRENDING_BEAR': '📉',
    'MEAN_REVERTING': '↩️',
    'NEUTRAL': '⚖️'
  }
  return icons[data.value?.regime] || '⏳'
})

const regimeLabel = computed(() => {
  const labels = {
    'TRENDING_BULL': 'TRENDING (Bull)',
    'TRENDING_BEAR': 'TRENDING (Bear)',
    'MEAN_REVERTING': 'MEAN REVERTING',
    'NEUTRAL': 'NEUTRAL'
  }
  return labels[data.value?.regime] || 'Loading...'
})

const isAnimated = computed(() => {
  return ['TRENDING_BULL', 'TRENDING_BEAR'].includes(data.value?.regime)
})

const regimeBackgroundClass = computed(() => {
  const classes = {
    'TRENDING_BULL': 'bg-gradient-to-br from-emerald-500/30 to-green-600/20 border border-emerald-500/30',
    'TRENDING_BEAR': 'bg-gradient-to-br from-red-500/30 to-rose-600/20 border border-red-500/30',
    'MEAN_REVERTING': 'bg-gradient-to-br from-cyan-500/30 to-blue-600/20 border border-cyan-500/30',
    'NEUTRAL': 'bg-gradient-to-br from-gray-500/30 to-slate-600/20 border border-gray-500/30'
  }
  return classes[data.value?.regime] || 'bg-gray-800/50 border border-gray-700/50'
})

const regimeAnimationClass = computed(() => {
  if (data.value?.regime === 'TRENDING_BULL') {
    return 'bg-gradient-to-r from-transparent via-emerald-400/30 to-transparent animate-shimmer'
  }
  if (data.value?.regime === 'TRENDING_BEAR') {
    return 'bg-gradient-to-r from-transparent via-red-400/30 to-transparent animate-shimmer'
  }
  return ''
})

const confidenceBarClass = computed(() => {
  const classes = {
    'TRENDING_BULL': 'bg-gradient-to-r from-emerald-500 to-green-400',
    'TRENDING_BEAR': 'bg-gradient-to-r from-red-500 to-rose-400',
    'MEAN_REVERTING': 'bg-gradient-to-r from-cyan-500 to-blue-400',
    'NEUTRAL': 'bg-gradient-to-r from-gray-500 to-slate-400'
  }
  return classes[data.value?.regime] || 'bg-gray-500'
})

const volatilityIcon = computed(() => {
  const icons = { 'HIGH': '🔴', 'NORMAL': '🟡', 'LOW': '🟢' }
  return icons[data.value?.volatility] || '🟡'
})

const volatilityTextClass = computed(() => {
  const classes = { 'HIGH': 'text-red-400', 'NORMAL': 'text-yellow-400', 'LOW': 'text-emerald-400' }
  return classes[data.value?.volatility] || 'text-gray-400'
})

const getTrendLabel = computed(() => {
  const strength = Math.abs(data.value?.trend_strength || 0)
  if (strength < 0.2) return 'Weak'
  if (strength < 0.4) return 'Moderate'
  if (strength < 0.6) return 'Strong'
  return 'Very Strong'
})

const hurstTextClass = computed(() => {
  const h = data.value?.hurst_exponent
  if (!h) return 'text-gray-400'
  if (h < 0.45) return 'text-cyan-400'
  if (h > 0.55) return 'text-orange-400'
  return 'text-gray-400'
})

const hurstInterpretation = computed(() => {
  const h = data.value?.hurst_exponent
  if (!h) return 'Unknown'
  if (h < 0.45) return 'Mean-Reverting'
  if (h > 0.55) return 'Trending'
  return 'Random Walk'
})

// Methods
const getTrendBarClass = (index) => {
  const strength = Math.abs(data.value?.trend_strength || 0)
  const activeBars = Math.ceil(strength * 5)
  const isBull = (data.value?.trend_strength || 0) > 0
  
  if (index <= activeBars) {
    return isBull ? 'bg-emerald-500' : 'bg-red-500'
  }
  return 'bg-gray-600'
}

const refresh = async () => {
  loading.value = true
  
  try {
    const response = await api.get(`/regime/current/${props.symbol}`, {
      params: { timeframe: props.timeframe }
    })
    
    const newData = response.data
    
    // Check for regime change
    if (previousRegime.value && previousRegime.value !== newData.regime) {
      emit('regime-change', {
        previous: previousRegime.value,
        current: newData.regime,
        symbol: props.symbol
      })
    }
    
    previousRegime.value = newData.regime
    data.value = newData
    
  } catch (err) {
    console.error('Failed to fetch regime:', err)
    // Use mock data for demo
    data.value = {
      regime: 'MEAN_REVERTING',
      volatility: 'NORMAL',
      regime_confidence: 72,
      volatility_percentile: 45,
      trend_strength: 0.15,
      mean_reversion_score: 0.65,
      regime_duration_bars: 24,
      hurst_exponent: 0.42,
      recommendation: 'Market appears mean-reverting. Favor counter-trend entries near Fibonacci retracement zones.'
    }
  } finally {
    loading.value = false
  }
}

const startAutoRefresh = () => {
  if (props.autoRefresh) {
    refreshTimer = setInterval(refresh, props.refreshInterval)
  }
}

const stopAutoRefresh = () => {
  if (refreshTimer) {
    clearInterval(refreshTimer)
    refreshTimer = null
  }
}

// Lifecycle
onMounted(() => {
  refresh()
  startAutoRefresh()
})

onUnmounted(() => {
  stopAutoRefresh()
})
</script>

<style scoped>
@keyframes shimmer {
  0% { transform: translateX(-100%); }
  100% { transform: translateX(100%); }
}

.animate-shimmer {
  animation: shimmer 2s infinite;
}
</style>
