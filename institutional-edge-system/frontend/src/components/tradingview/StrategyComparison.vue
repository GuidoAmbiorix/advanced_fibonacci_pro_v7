<template>
  <div class="strategy-comparison">
    <div class="comparison-header">
      <h3 class="text-lg font-bold text-white">Strategy Comparison</h3>
      <div class="strategy-selectors">
        <select v-model="strategyA" @change="loadComparison" class="strategy-select">
          <option value="">Select Strategy A</option>
          <option v-for="session in backtestSessions" :key="session.id" :value="session.id">
            {{ session.symbol }} {{ session.timeframe }} - {{ formatDate(session.created_at) }}
          </option>
        </select>
        <span class="vs-label">VS</span>
        <select v-model="strategyB" @change="loadComparison" class="strategy-select">
          <option value="">Select Strategy B</option>
          <option v-for="session in backtestSessions" :key="session.id" :value="session.id">
            {{ session.symbol }} {{ session.timeframe }} - {{ formatDate(session.created_at) }}
          </option>
        </select>
      </div>
    </div>

    <!-- Loading State -->
    <div v-if="loading" class="loading-state">
      <div class="spinner"></div>
      <p class="text-gray-400">Comparing strategies...</p>
    </div>

    <!-- Comparison Table -->
    <div v-else-if="comparisonData" class="comparison-content">
      <div class="metrics-comparison-table">
        <table class="w-full">
          <thead>
            <tr class="border-b border-gray-700">
              <th class="text-left py-2 text-gray-400">Metric</th>
              <th class="text-right py-2 text-gray-400">Strategy A</th>
              <th class="text-right py-2 text-gray-400">Strategy B</th>
              <th class="text-right py-2 text-gray-400">Winner</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="metric in comparisonData.metrics"
              :key="metric.metric_name"
              class="border-b border-gray-800"
            >
              <td class="py-3 text-gray-300">{{ metric.metric_name }}</td>
              <td class="text-right font-semibold text-white">{{ formatMetric(metric.strategy_a_value, metric.metric_name) }}</td>
              <td class="text-right font-semibold text-white">{{ formatMetric(metric.strategy_b_value, metric.metric_name) }}</td>
              <td class="text-right font-bold">
                <span
                  :class="{
                    'text-green-400': metric.winner === 'A',
                    'text-red-400': metric.winner === 'B',
                    'text-gray-400': metric.winner === 'TIE'
                  }"
                >
                  {{ metric.winner }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Summary -->
      <div class="comparison-summary">
        <div class="summary-card">
          <h4 class="font-semibold text-white mb-2">Summary</h4>
          <p class="text-sm text-gray-400">
            Strategy {{ getWinner() }} performs better overall with {{ getWinCount() }} winning metrics.
          </p>
        </div>
      </div>
    </div>

    <!-- Empty State -->
    <div v-else class="empty-state">
      <ArrowsRightLeftIcon class="w-12 h-12 text-gray-600 mx-auto mb-2" />
      <p class="text-gray-400">Select two strategies to compare</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { ArrowsRightLeftIcon } from '@heroicons/vue/24/outline'
import axios from 'axios'

const strategyA = ref<number | string>('')
const strategyB = ref<number | string>('')
const backtestSessions = ref<any[]>([])
const loading = ref(false)
const comparisonData = ref<any>(null)

onMounted(async () => {
  // Load backtest sessions
  try {
    const response = await axios.get('/api/backtest/history')
    backtestSessions.value = response.data
  } catch (error) {
    console.error('Failed to load backtest sessions:', error)
  }
})

async function loadComparison() {
  if (!strategyA.value || !strategyB.value) {
    comparisonData.value = null
    return
  }

  loading.value = true
  try {
    const response = await axios.post('/api/comparisons', {
      name: 'Comparison',
      session_ids: [Number(strategyA.value), Number(strategyB.value)]
    })
    comparisonData.value = response.data
  } catch (error) {
    console.error('Failed to create comparison:', error)
  } finally {
    loading.value = false
  }
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString()
}

function formatMetric(value: number, metricName: string): string {
  if (metricName.includes('Profit') && metricName !== 'Profit Factor') {
    return `$${value.toFixed(2)}`
  }
  if (metricName.includes('Rate') || metricName.includes('Drawdown')) {
    return `${value.toFixed(2)}%`
  }
  return value.toFixed(2)
}

function getWinner(): string {
  if (!comparisonData.value) return ''
  const aWins = comparisonData.value.metrics.filter((m: any) => m.winner === 'A').length
  const bWins = comparisonData.value.metrics.filter((m: any) => m.winner === 'B').length
  return aWins > bWins ? 'A' : 'B'
}

function getWinCount(): number {
  if (!comparisonData.value) return 0
  const winner = getWinner()
  return comparisonData.value.metrics.filter((m: any) => m.winner === winner).length
}
</script>

<style scoped>
.strategy-comparison {
  @apply bg-gray-800 rounded-lg border border-gray-700 p-4;
}

.comparison-header {
  @apply mb-4;
}

.strategy-selectors {
  @apply flex items-center gap-2 mt-2;
}

.strategy-select {
  @apply flex-1 bg-gray-700 text-white px-3 py-2 rounded border border-gray-600;
}

.vs-label {
  @apply text-gray-400 font-bold;
}

.loading-state {
  @apply flex flex-col items-center justify-center py-12;
}

.spinner {
  @apply w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mb-2;
}

.comparison-content {
  @apply space-y-4;
}

.metrics-comparison-table {
  @apply overflow-x-auto;
}

.comparison-summary {
  @apply mt-4 p-4 bg-gray-900 rounded-lg;
}

.empty-state {
  @apply text-center py-12;
}
</style>
