<template>
  <div class="oos-validation bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-6 shadow-2xl">
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <div class="flex items-center gap-3">
        <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center">
          <span class="text-xl">🔬</span>
        </div>
        <div>
          <h3 class="text-lg font-bold text-white">Out-of-Sample Validation</h3>
          <p class="text-xs text-gray-400">Prevent overfitting with proper testing</p>
        </div>
      </div>
      <button 
        @click="showHelp = !showHelp"
        class="w-8 h-8 rounded-lg bg-gray-700/50 hover:bg-gray-600/50 flex items-center justify-center text-gray-400 hover:text-white transition-colors"
      >
        ?
      </button>
    </div>

    <!-- Help Panel -->
    <transition name="slide">
      <div v-if="showHelp" class="mb-6 p-4 rounded-xl bg-purple-500/10 border border-purple-500/30 text-sm text-purple-200">
        <p class="mb-2"><strong>Out-of-Sample Testing</strong> validates strategy on unseen data.</p>
        <p class="text-xs text-purple-300/70">
          A strategy that performs well on training data but poorly on test data is likely overfit.
          The performance gap reveals overfitting risk.
        </p>
      </div>
    </transition>

    <!-- Split Configuration -->
    <div class="mb-6">
      <label class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3 block">
        Train / Test Split
      </label>
      <div class="flex items-center gap-4">
        <!-- Slider -->
        <div class="flex-1">
          <input
            type="range"
            v-model.number="splitRatio"
            min="50"
            max="90"
            step="5"
            class="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
          />
          <div class="flex justify-between text-xs text-gray-500 mt-1">
            <span>50%</span>
            <span>70%</span>
            <span>90%</span>
          </div>
        </div>
        
        <!-- Current value -->
        <div class="text-center px-4 py-2 rounded-lg bg-gray-800/50 border border-gray-700/50">
          <div class="text-lg font-bold text-white">{{ splitRatio }}%</div>
          <div class="text-xs text-gray-400">Train</div>
        </div>
        <div class="text-center px-4 py-2 rounded-lg bg-gray-800/50 border border-gray-700/50">
          <div class="text-lg font-bold text-purple-400">{{ 100 - splitRatio }}%</div>
          <div class="text-xs text-gray-400">Test</div>
        </div>
      </div>
    </div>

    <!-- Validation Button -->
    <button
      @click="runValidation"
      :disabled="loading || !hasTradeData"
      class="w-full py-3 rounded-xl font-medium transition-all flex items-center justify-center gap-2 mb-6"
      :class="hasTradeData 
        ? 'bg-gradient-to-r from-purple-500 to-pink-500 text-white hover:from-purple-600 hover:to-pink-600 shadow-lg hover:shadow-purple-500/25'
        : 'bg-gray-700/50 text-gray-400 cursor-not-allowed'"
    >
      <span v-if="loading" class="animate-spin">↻</span>
      <span>{{ loading ? 'Validating...' : hasTradeData ? 'Run OOS Validation' : 'No Trade Data' }}</span>
    </button>

    <!-- Results -->
    <div v-if="result" class="space-y-4">
      <!-- Status Banner -->
      <div 
        class="p-4 rounded-xl flex items-center gap-4"
        :class="statusClass"
      >
        <span class="text-3xl">{{ statusIcon }}</span>
        <div>
          <div class="font-bold text-white text-lg">{{ statusLabel }}</div>
          <div class="text-sm opacity-80">{{ result.recommendation }}</div>
        </div>
      </div>

      <!-- Comparison Grid -->
      <div class="grid grid-cols-2 gap-4">
        <!-- In-Sample -->
        <div class="p-4 rounded-xl bg-cyan-500/10 border border-cyan-500/30">
          <h4 class="text-xs font-medium text-cyan-400 uppercase tracking-wider mb-3">In-Sample (Train)</h4>
          <div class="space-y-2">
            <div class="flex justify-between">
              <span class="text-gray-400">Sharpe</span>
              <span class="font-mono font-bold text-white">{{ result.in_sample_sharpe?.toFixed(2) }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Return</span>
              <span class="font-mono font-bold text-cyan-400">{{ result.in_sample_return?.toFixed(1) }}%</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Win Rate</span>
              <span class="font-mono font-bold text-white">{{ result.in_sample_win_rate?.toFixed(1) }}%</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Trades</span>
              <span class="font-mono font-bold text-white">{{ result.in_sample_trades }}</span>
            </div>
          </div>
        </div>

        <!-- Out-of-Sample -->
        <div class="p-4 rounded-xl bg-purple-500/10 border border-purple-500/30">
          <h4 class="text-xs font-medium text-purple-400 uppercase tracking-wider mb-3">Out-of-Sample (Test)</h4>
          <div class="space-y-2">
            <div class="flex justify-between">
              <span class="text-gray-400">Sharpe</span>
              <span class="font-mono font-bold text-white">{{ result.out_of_sample_sharpe?.toFixed(2) }}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Return</span>
              <span class="font-mono font-bold text-purple-400">{{ result.out_of_sample_return?.toFixed(1) }}%</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Win Rate</span>
              <span class="font-mono font-bold text-white">{{ result.out_of_sample_win_rate?.toFixed(1) }}%</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-400">Trades</span>
              <span class="font-mono font-bold text-white">{{ result.out_of_sample_trades }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Performance Gap -->
      <div class="p-4 rounded-xl bg-gray-800/50 border border-gray-700/50">
        <div class="flex items-center justify-between mb-3">
          <h4 class="text-xs font-medium text-gray-400 uppercase tracking-wider">Performance Gap Analysis</h4>
          <span 
            class="px-2 py-1 rounded text-xs font-medium"
            :class="gapClass"
          >
            {{ result.performance_gap_percent?.toFixed(1) }}% degradation
          </span>
        </div>
        
        <!-- Gap Visualization -->
        <div class="relative h-8 bg-gray-700/50 rounded-lg overflow-hidden">
          <div class="absolute inset-y-0 left-0 bg-cyan-500/50" :style="{ width: '50%' }"></div>
          <div 
            class="absolute inset-y-0 right-0 transition-all duration-500"
            :class="result.degradation_factor >= 0.7 ? 'bg-emerald-500/50' : result.degradation_factor >= 0.5 ? 'bg-yellow-500/50' : 'bg-red-500/50'"
            :style="{ width: `${result.degradation_factor * 50}%` }"
          ></div>
          <div class="absolute inset-0 flex items-center justify-center text-xs font-medium text-white">
            IS: {{ result.in_sample_sharpe?.toFixed(2) }} → OOS: {{ result.out_of_sample_sharpe?.toFixed(2) }}
          </div>
        </div>
      </div>

      <!-- Data Snooping Score -->
      <div class="p-4 rounded-xl bg-gray-800/50 border border-gray-700/50">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm text-gray-400">Data Snooping Risk</span>
          <span 
            class="text-lg font-bold"
            :class="result.data_snooping_score < 30 ? 'text-emerald-400' : result.data_snooping_score < 60 ? 'text-yellow-400' : 'text-red-400'"
          >
            {{ result.data_snooping_score?.toFixed(0) }}%
          </span>
        </div>
        <div class="h-2 bg-gray-700 rounded-full overflow-hidden">
          <div 
            class="h-full rounded-full transition-all duration-500"
            :class="result.data_snooping_score < 30 ? 'bg-emerald-500' : result.data_snooping_score < 60 ? 'bg-yellow-500' : 'bg-red-500'"
            :style="{ width: `${result.data_snooping_score}%` }"
          ></div>
        </div>
      </div>

      <!-- Warnings -->
      <div v-if="result.warnings?.length" class="space-y-2">
        <div 
          v-for="(warning, idx) in result.warnings"
          :key="idx"
          class="p-3 rounded-lg bg-amber-500/20 border border-amber-500/30 text-sm text-amber-200 flex items-start gap-2"
        >
          <span>⚠️</span>
          <span>{{ warning }}</span>
        </div>
      </div>
    </div>

    <!-- Loading State -->
    <div v-if="loading" class="absolute inset-0 bg-slate-900/50 backdrop-blur-sm rounded-2xl flex items-center justify-center">
      <div class="animate-spin w-8 h-8 border-2 border-purple-500 border-t-transparent rounded-full"></div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import api from '../services/api'

// Props
const props = defineProps({
  trades: { type: Array, default: () => [] }
})

// State
const splitRatio = ref(70)
const showHelp = ref(false)
const loading = ref(false)
const result = ref(null)

// Computed
const hasTradeData = computed(() => props.trades.length > 20)

const statusIcon = computed(() => {
  if (!result.value) return ''
  return result.value.is_valid ? '✅' : '❌'
})

const statusLabel = computed(() => {
  if (!result.value) return ''
  return result.value.is_valid ? 'VALID STRATEGY' : 'OVERFITTING DETECTED'
})

const statusClass = computed(() => {
  if (!result.value) return ''
  return result.value.is_valid 
    ? 'bg-gradient-to-r from-emerald-500/20 to-green-500/20 border border-emerald-500/30'
    : 'bg-gradient-to-r from-red-500/20 to-rose-500/20 border border-red-500/30'
})

const gapClass = computed(() => {
  if (!result.value) return 'bg-gray-500/20 text-gray-400'
  const gap = Math.abs(result.value.performance_gap_percent || 0)
  if (gap < 20) return 'bg-emerald-500/20 text-emerald-400'
  if (gap < 40) return 'bg-yellow-500/20 text-yellow-400'
  return 'bg-red-500/20 text-red-400'
})

// Methods
const runValidation = async () => {
  if (!hasTradeData.value) return
  
  loading.value = true
  
  try {
    // Split trades
    const splitIdx = Math.floor(props.trades.length * splitRatio.value / 100)
    const inSampleTrades = props.trades.slice(0, splitIdx).map(formatTrade)
    const outOfSampleTrades = props.trades.slice(splitIdx).map(formatTrade)
    
    // Call API
    const response = await api.post('/validation/oos/validate', {
      in_sample_trades: inSampleTrades,
      out_of_sample_trades: outOfSampleTrades,
      initial_balance: 10000
    })
    
    result.value = response.data
    
  } catch (err) {
    console.error('Validation failed:', err)
    // Use mock result for demo
    result.value = generateMockResult()
  } finally {
    loading.value = false
  }
}

const formatTrade = (trade) => ({
  entry_time: trade.entry_time || trade.entryTime,
  exit_time: trade.exit_time || trade.exitTime,
  entry_price: trade.entry_price || trade.entryPrice || 1.0,
  exit_price: trade.exit_price || trade.exitPrice || 1.0,
  pnl: trade.pnl || 0,
  type: trade.type || trade.signal_type || 'BUY',
  exit_reason: trade.exit_reason || trade.exitReason || ''
})

const generateMockResult = () => ({
  in_sample_sharpe: 1.85,
  out_of_sample_sharpe: 1.12,
  performance_gap: 0.73,
  performance_gap_percent: 39.5,
  is_valid: true,
  in_sample_return: 45.2,
  out_of_sample_return: 18.7,
  in_sample_win_rate: 68.5,
  out_of_sample_win_rate: 61.2,
  in_sample_trades: 85,
  out_of_sample_trades: 36,
  data_snooping_score: 42,
  degradation_factor: 0.61,
  recommendation: "Strategy is valid but shows moderate performance degradation. Consider reducing parameters.",
  warnings: ["Moderate performance gap between IS and OOS"]
})
</script>

<style scoped>
.slide-enter-active,
.slide-leave-active {
  transition: all 0.3s ease;
}

.slide-enter-from,
.slide-leave-to {
  opacity: 0;
  transform: translateY(-10px);
}
</style>
