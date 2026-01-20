<template>
  <div class="enhanced-metrics bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-6 shadow-2xl">
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <div class="flex items-center gap-3">
        <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-cyan-500 to-blue-500 flex items-center justify-center">
          <span class="text-xl">📈</span>
        </div>
        <div>
          <h3 class="text-lg font-bold text-white">Quantitative Metrics</h3>
          <p class="text-xs text-gray-400">Advanced performance analysis</p>
        </div>
      </div>
    </div>

    <!-- Primary Metrics Grid -->
    <div class="grid grid-cols-4 gap-4 mb-6">
      <!-- Sharpe Ratio -->
      <div class="metric-card bg-gray-800/50 border border-gray-700/50 rounded-xl p-4">
        <div class="text-xs text-gray-400 uppercase tracking-wider mb-1">Sharpe Ratio</div>
        <div class="text-2xl font-bold" :class="sharpeClass">{{ metrics?.sharpe_ratio?.toFixed(2) || '0.00' }}</div>
        <div class="text-xs mt-1" :class="sharpeClass">{{ sharpeLabel }}</div>
      </div>

      <!-- Sortino Ratio -->
      <div class="metric-card bg-gray-800/50 border border-gray-700/50 rounded-xl p-4">
        <div class="text-xs text-gray-400 uppercase tracking-wider mb-1">Sortino Ratio</div>
        <div class="text-2xl font-bold" :class="sortinoClass">{{ metrics?.sortino_ratio?.toFixed(2) || '0.00' }}</div>
        <div class="text-xs mt-1 text-gray-500">Downside risk</div>
      </div>

      <!-- Calmar Ratio -->
      <div class="metric-card bg-gray-800/50 border border-gray-700/50 rounded-xl p-4">
        <div class="text-xs text-gray-400 uppercase tracking-wider mb-1">Calmar Ratio</div>
        <div class="text-2xl font-bold" :class="calmarClass">{{ metrics?.calmar_ratio?.toFixed(2) || '0.00' }}</div>
        <div class="text-xs mt-1 text-gray-500">Return/MaxDD</div>
      </div>

      <!-- CAGR -->
      <div class="metric-card bg-gray-800/50 border border-gray-700/50 rounded-xl p-4">
        <div class="text-xs text-gray-400 uppercase tracking-wider mb-1">CAGR</div>
        <div class="text-2xl font-bold" :class="metrics?.cagr > 0 ? 'text-emerald-400' : 'text-red-400'">
          {{ metrics?.cagr?.toFixed(1) || '0.0' }}%
        </div>
        <div class="text-xs mt-1 text-gray-500">Annual growth</div>
      </div>
    </div>

    <!-- Secondary Metrics -->
    <div class="grid grid-cols-3 gap-4 mb-6">
      <!-- Omega Ratio -->
      <div class="metric-card bg-gradient-to-r from-purple-500/10 to-pink-500/10 border border-purple-500/20 rounded-xl p-4">
        <div class="flex items-center justify-between">
          <div>
            <div class="text-xs text-purple-400 uppercase tracking-wider mb-1">Omega Ratio</div>
            <div class="text-xl font-bold text-white">{{ metrics?.omega_ratio?.toFixed(2) || '1.00' }}</div>
          </div>
          <div class="text-3xl">Ω</div>
        </div>
        <div class="text-xs text-gray-400 mt-2">Probability-weighted gain/loss</div>
      </div>

      <!-- Kelly Fraction -->
      <div class="metric-card bg-gradient-to-r from-emerald-500/10 to-cyan-500/10 border border-emerald-500/20 rounded-xl p-4">
        <div class="flex items-center justify-between">
          <div>
            <div class="text-xs text-emerald-400 uppercase tracking-wider mb-1">Kelly Fraction</div>
            <div class="text-xl font-bold text-white">{{ (metrics?.kelly_fraction * 100)?.toFixed(1) || '0.0' }}%</div>
          </div>
          <div class="text-xs text-cyan-400">
            Half: {{ (metrics?.half_kelly * 100)?.toFixed(1) || '0.0' }}%
          </div>
        </div>
        <div class="text-xs text-gray-400 mt-2">Optimal position size</div>
      </div>

      <!-- Ulcer Index -->
      <div class="metric-card bg-gradient-to-r from-orange-500/10 to-red-500/10 border border-orange-500/20 rounded-xl p-4">
        <div class="flex items-center justify-between">
          <div>
            <div class="text-xs text-orange-400 uppercase tracking-wider mb-1">Ulcer Index</div>
            <div class="text-xl font-bold text-white">{{ metrics?.ulcer_index?.toFixed(2) || '0.00' }}</div>
          </div>
          <span class="text-2xl">📉</span>
        </div>
        <div class="text-xs text-gray-400 mt-2">Downside volatility</div>
      </div>
    </div>

    <!-- Drawdown Analysis -->
    <div class="bg-gray-800/30 rounded-xl p-5 mb-6">
      <h4 class="text-sm font-medium text-white mb-4 flex items-center gap-2">
        <span>📊</span>
        <span>Drawdown Analysis</span>
      </h4>
      
      <div class="grid grid-cols-3 gap-4">
        <!-- Max Drawdown -->
        <div class="text-center p-3 rounded-lg bg-gray-800/50">
          <div class="text-xs text-gray-400 mb-1">Max Drawdown</div>
          <div class="text-xl font-bold text-red-400">
            -{{ metrics?.max_drawdown_percent?.toFixed(1) || '0.0' }}%
          </div>
          <div class="text-xs text-gray-500">${{ metrics?.max_drawdown?.toFixed(0) || '0' }}</div>
        </div>

        <!-- Max DD Duration -->
        <div class="text-center p-3 rounded-lg bg-gray-800/50">
          <div class="text-xs text-gray-400 mb-1">Max DD Duration</div>
          <div class="text-xl font-bold text-orange-400">
            {{ metrics?.max_drawdown_duration_days?.toFixed(0) || '0' }}
          </div>
          <div class="text-xs text-gray-500">days</div>
        </div>

        <!-- Average DD Duration -->
        <div class="text-center p-3 rounded-lg bg-gray-800/50">
          <div class="text-xs text-gray-400 mb-1">Avg Recovery</div>
          <div class="text-xl font-bold text-yellow-400">
            {{ metrics?.avg_drawdown_duration_days?.toFixed(1) || '0.0' }}
          </div>
          <div class="text-xs text-gray-500">days</div>
        </div>
      </div>
    </div>

    <!-- Trade Distribution -->
    <div class="grid grid-cols-3 gap-4">
      <!-- Best Trade -->
      <div class="text-center p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/20">
        <div class="text-xs text-gray-400 mb-1">Best Trade</div>
        <div class="text-lg font-bold text-emerald-400">
          +${{ metrics?.best_trade?.toFixed(0) || '0' }}
        </div>
      </div>

      <!-- Median Trade -->
      <div class="text-center p-3 rounded-lg bg-gray-500/10 border border-gray-500/20">
        <div class="text-xs text-gray-400 mb-1">Median Trade</div>
        <div class="text-lg font-bold text-white">
          ${{ metrics?.median_trade?.toFixed(0) || '0' }}
        </div>
      </div>

      <!-- Worst Trade -->
      <div class="text-center p-3 rounded-lg bg-red-500/10 border border-red-500/20">
        <div class="text-xs text-gray-400 mb-1">Worst Trade</div>
        <div class="text-lg font-bold text-red-400">
          ${{ metrics?.worst_trade?.toFixed(0) || '0' }}
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  metrics: {
    type: Object,
    default: () => ({
      sharpe_ratio: 1.5,
      sortino_ratio: 2.1,
      calmar_ratio: 2.8,
      cagr: 25.5,
      omega_ratio: 1.45,
      kelly_fraction: 0.18,
      half_kelly: 0.09,
      ulcer_index: 4.2,
      max_drawdown_percent: 12.5,
      max_drawdown: 1250,
      max_drawdown_duration_days: 15,
      avg_drawdown_duration_days: 5.2,
      best_trade: 523,
      median_trade: 85,
      worst_trade: -312
    })
  }
})

const sharpeClass = computed(() => {
  const sharpe = props.metrics?.sharpe_ratio || 0
  if (sharpe >= 2) return 'text-emerald-400'
  if (sharpe >= 1) return 'text-cyan-400'
  if (sharpe >= 0.5) return 'text-yellow-400'
  return 'text-red-400'
})

const sharpeLabel = computed(() => {
  const sharpe = props.metrics?.sharpe_ratio || 0
  if (sharpe >= 2) return 'Excellent'
  if (sharpe >= 1) return 'Good'
  if (sharpe >= 0.5) return 'Acceptable'
  return 'Poor'
})

const sortinoClass = computed(() => {
  const sortino = props.metrics?.sortino_ratio || 0
  if (sortino >= 2) return 'text-emerald-400'
  if (sortino >= 1) return 'text-cyan-400'
  return 'text-yellow-400'
})

const calmarClass = computed(() => {
  const calmar = props.metrics?.calmar_ratio || 0
  if (calmar >= 3) return 'text-emerald-400'
  if (calmar >= 1.5) return 'text-cyan-400'
  if (calmar >= 1) return 'text-yellow-400'
  return 'text-red-400'
})
</script>

<style scoped>
.metric-card {
  transition: all 0.3s ease;
}

.metric-card:hover {
  transform: translateY(-2px);
  border-color: rgba(255, 255, 255, 0.2);
}
</style>
