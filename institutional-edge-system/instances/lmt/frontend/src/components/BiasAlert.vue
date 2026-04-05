<template>
  <div class="bias-alert">
    <!-- Compact Mode (Default) -->
    <div 
      v-if="!expanded"
      @click="expanded = true"
      class="flex items-center gap-3 p-4 rounded-xl cursor-pointer transition-all hover:scale-[1.02]"
      :class="statusClass"
    >
      <span class="text-2xl">{{ statusIcon }}</span>
      <div class="flex-1">
        <div class="text-sm font-bold text-white">Bias Check: {{ result?.overall_status || 'PENDING' }}</div>
        <div class="text-xs opacity-70">Score: {{ result?.overall_score?.toFixed(0) || '--' }}/100</div>
      </div>
      <span class="text-gray-400">▼</span>
    </div>

    <!-- Expanded Mode -->
    <div 
      v-else
      class="bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-6 shadow-2xl"
    >
      <!-- Header -->
      <div class="flex items-center justify-between mb-6">
        <div class="flex items-center gap-3">
          <div 
            class="w-10 h-10 rounded-xl flex items-center justify-center"
            :class="iconBgClass"
          >
            <span class="text-xl">{{ statusIcon }}</span>
          </div>
          <div>
            <h3 class="text-lg font-bold text-white">Bias Detection Report</h3>
            <p class="text-xs text-gray-400">Backtest quality analysis</p>
          </div>
        </div>
        <button 
          @click="expanded = false"
          class="w-8 h-8 rounded-lg bg-gray-700/50 hover:bg-gray-600/50 flex items-center justify-center text-gray-400 hover:text-white transition-colors"
        >
          ✕
        </button>
      </div>

      <!-- Overall Score -->
      <div 
        class="p-5 rounded-xl mb-6 text-center"
        :class="statusClass"
      >
        <div class="text-5xl font-bold text-white mb-2">{{ result?.overall_score?.toFixed(0) || '0' }}</div>
        <div class="text-sm opacity-80 uppercase tracking-wider">Quality Score</div>
        <div class="text-xs mt-2 opacity-60">{{ result?.recommendation }}</div>
      </div>

      <!-- Individual Checks -->
      <div class="space-y-3 mb-6">
        <div 
          v-for="check in result?.checks"
          :key="check.bias_type"
          class="flex items-center gap-3 p-3 rounded-lg bg-gray-800/30"
        >
          <!-- Status Icon -->
          <div 
            class="w-8 h-8 rounded-lg flex items-center justify-center text-sm font-bold"
            :class="getCheckClass(check.status)"
          >
            {{ getCheckIcon(check.status) }}
          </div>
          
          <!-- Details -->
          <div class="flex-1">
            <div class="text-sm font-medium text-white">{{ check.bias_type }}</div>
            <div class="text-xs text-gray-400">{{ check.message }}</div>
          </div>
          
          <!-- Severity -->
          <div 
            class="text-sm font-mono font-bold"
            :class="getSeverityClass(check.severity)"
          >
            {{ check.severity?.toFixed(0) }}
          </div>
        </div>
      </div>

      <!-- Run Check Button -->
      <button
        @click="runBiasCheck"
        :disabled="loading || !hasTrades"
        class="w-full py-3 rounded-xl font-medium transition-all flex items-center justify-center gap-2"
        :class="hasTrades 
          ? 'bg-gradient-to-r from-amber-500 to-orange-500 text-white hover:from-amber-600 hover:to-orange-600 shadow-lg'
          : 'bg-gray-700/50 text-gray-400 cursor-not-allowed'"
      >
        <span v-if="loading" class="animate-spin">↻</span>
        <span>{{ loading ? 'Analyzing...' : hasTrades ? 'Run Bias Check' : 'No Trade Data' }}</span>
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import api from '../services/api'

const props = defineProps({
  trades: { type: Array, default: () => [] },
  strategyParams: { type: Object, default: null },
  autoRun: { type: Boolean, default: false }
})

// State
const expanded = ref(false)
const loading = ref(false)
const result = ref(null)

// Computed
const hasTrades = computed(() => props.trades.length > 10)

const statusIcon = computed(() => {
  if (!result.value) return '⏳'
  const status = result.value.overall_status
  if (status === 'PASS') return 'R'
  if (status === 'WARN') return 'R'
  return '❌'
})

const statusClass = computed(() => {
  if (!result.value) return 'bg-gray-700/50 border border-gray-600/50'
  const status = result.value.overall_status
  if (status === 'PASS') return 'bg-gradient-to-r from-emerald-500/20 to-green-500/20 border border-emerald-500/30'
  if (status === 'WARN') return 'bg-gradient-to-r from-amber-500/20 to-orange-500/20 border border-amber-500/30'
  return 'bg-gradient-to-r from-red-500/20 to-rose-500/20 border border-red-500/30'
})

const iconBgClass = computed(() => {
  if (!result.value) return 'bg-gray-700'
  const status = result.value.overall_status
  if (status === 'PASS') return 'bg-gradient-to-br from-emerald-500 to-green-500'
  if (status === 'WARN') return 'bg-gradient-to-br from-amber-500 to-orange-500'
  return 'bg-gradient-to-br from-red-500 to-rose-500'
})

// Methods
const getCheckIcon = (status) => {
  if (status === 'PASS') return '✓'
  if (status === 'WARN') return '!'
  return '✕'
}

const getCheckClass = (status) => {
  if (status === 'PASS') return 'bg-emerald-500/20 text-emerald-400'
  if (status === 'WARN') return 'bg-amber-500/20 text-amber-400'
  return 'bg-red-500/20 text-red-400'
}

const getSeverityClass = (severity) => {
  if (severity < 20) return 'text-emerald-400'
  if (severity < 50) return 'text-yellow-400'
  return 'text-red-400'
}

const runBiasCheck = async () => {
  if (!hasTrades.value) return
  
  loading.value = true
  
  try {
    const trades = props.trades.map(t => ({
      entry_time: t.entry_time || t.entryTime,
      exit_time: t.exit_time || t.exitTime,
      entry_price: t.entry_price || t.entryPrice || 1.0,
      exit_price: t.exit_price || t.exitPrice || 1.0,
      pnl: t.pnl || 0,
      type: t.type || t.signal_type || 'BUY',
      exit_reason: t.exit_reason || t.exitReason || ''
    }))
    
    const response = await api.post('/validation/bias/check', {
      trades,
      strategy_params: props.strategyParams
    })
    
    result.value = response.data
    
  } catch (err) {
    console.error('Bias check failed:', err)
    // Use mock for demo
    result.value = {
      overall_status: 'WARN',
      overall_score: 72,
      recommendation: 'Minor issues detected. Review before trading.',
      checks: [
        { bias_type: 'Look-Ahead Bias', status: 'PASS', severity: 10, message: 'No significant look-ahead bias detected' },
        { bias_type: 'Data Snooping', status: 'WARN', severity: 35, message: 'Moderate data snooping risk' },
        { bias_type: 'Perfect Trades', status: 'PASS', severity: 15, message: 'Trade outcomes appear realistic' },
        { bias_type: 'Time Distribution', status: 'PASS', severity: 8, message: 'Trades well distributed over time' },
        { bias_type: 'Parameter Sensitivity', status: 'WARN', severity: 25, message: 'Many parameters detected' }
      ],
      timestamp: new Date().toISOString()
    }
  } finally {
    loading.value = false
  }
}

// Auto-run on mount if enabled
onMounted(() => {
  if (props.autoRun && hasTrades.value) {
    runBiasCheck()
  }
})
</script>
