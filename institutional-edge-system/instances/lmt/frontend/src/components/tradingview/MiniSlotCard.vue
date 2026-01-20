<template>
  <div class="mini-slot-card" @click="$emit('expand', slotId)">
    <!-- Header -->
    <div class="card-header">
      <div class="symbol-info">
        <h3 class="font-bold text-lg text-white">{{ slot.symbol }}</h3>
        <span class="timeframe-badge">{{ slot.timeframe }}</span>
      </div>
      <div class="status-indicators">
        <span
          class="status-badge"
          :class="{
            'bg-green-500': slot.status === 'ACTIVE',
            'bg-yellow-500': slot.status === 'PAUSED',
            'bg-red-500': slot.status === 'ERROR'
          }"
        >
          {{ slot.status }}
        </span>
        <span v-if="slot.activeSignal" class="signal-badge animate-pulse">
          SIGNAL
        </span>
      </div>
    </div>

    <!-- Mini Chart Placeholder -->
    <div class="mini-chart" ref="chartContainer">
      <div class="chart-placeholder">
        <ChartBarIcon class="w-12 h-12 text-gray-600" />
        <span class="text-xs text-gray-500">Chart preview</span>
      </div>
    </div>

    <!-- Quick Stats -->
    <div class="quick-stats">
      <div class="stat">
        <span class="stat-label">Price</span>
        <span class="stat-value">{{ formatPrice(latestPrice) }}</span>
      </div>
      <div class="stat">
        <span class="stat-label">P&L Today</span>
        <span
          class="stat-value"
          :class="dailyPnL >= 0 ? 'text-green-400' : 'text-red-400'"
        >
          {{ dailyPnL >= 0 ? '+' : '' }}${{ dailyPnL.toFixed(2) }}
        </span>
      </div>
      <div class="stat">
        <span class="stat-label">Trades</span>
        <span class="stat-value">{{ totalTrades }}</span>
      </div>
    </div>

    <!-- Active Signal Preview -->
    <div v-if="slot.activeSignal" class="signal-preview">
      <div class="flex items-center justify-between">
        <span class="signal-type" :class="slot.activeSignal.type === 'BUY' ? 'text-green-400' : 'text-red-400'">
          {{ slot.activeSignal.type }}
        </span>
        <span class="signal-price text-sm text-gray-300">@ {{ slot.activeSignal.entry_price }}</span>
      </div>
      <div class="text-xs text-gray-400">
        Score: {{ slot.activeSignal.confluence_score }}/10
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { ChartBarIcon } from '@heroicons/vue/24/outline'
import axios from 'axios'

const props = defineProps<{
  slotId: number
}>()

const emit = defineEmits(['expand'])

const chartContainer = ref<HTMLElement>()
const slot = ref<any>({
  symbol: 'Loading...',
  timeframe: '',
  status: 'LOADING',
  activeSignal: null
})
const latestPrice = ref(0)
const dailyPnL = ref(0)
const totalTrades = ref(0)

onMounted(async () => {
  // Load slot data
  try {
    const response = await axios.get(`/api/slots/${props.slotId}`)
    slot.value = response.data
    slot.value.status = slot.value.enabled ? 'ACTIVE' : 'PAUSED'

    // Load quick stats
    const statsResponse = await axios.get(`/api/slots/${props.slotId}/quick-stats`)
    latestPrice.value = statsResponse.data.latest_price || 0
    dailyPnL.value = statsResponse.data.daily_pnl || 0
    totalTrades.value = statsResponse.data.total_trades || 0

    if (statsResponse.data.active_signal) {
      slot.value.activeSignal = statsResponse.data.active_signal
    }
  } catch (error) {
    console.error(`Failed to load slot ${props.slotId}:`, error)
    slot.value.status = 'ERROR'
  }

  // TODO: Initialize mini chart with lightweight-charts library
})

function formatPrice(price: number): string {
  if (price === 0) return 'N/A'
  return price.toFixed(5)
}
</script>

<style scoped>
.mini-slot-card {
  @apply bg-gray-800 border border-gray-700 rounded-lg p-3 cursor-pointer hover:border-blue-500 transition-all;
}

.card-header {
  @apply flex items-start justify-between mb-2;
}

.timeframe-badge {
  @apply text-xs bg-gray-700 px-2 py-0.5 rounded text-gray-300;
}

.status-indicators {
  @apply flex gap-1;
}

.status-badge, .signal-badge {
  @apply text-xs px-2 py-0.5 rounded font-medium text-white;
}

.signal-badge {
  @apply bg-blue-600 text-white;
}

.mini-chart {
  @apply w-full h-32 mb-2 bg-gray-900 rounded flex items-center justify-center;
}

.chart-placeholder {
  @apply flex flex-col items-center gap-1;
}

.quick-stats {
  @apply grid grid-cols-3 gap-2 text-center border-t border-gray-700 pt-2;
}

.stat-label {
  @apply text-xs text-gray-400 block;
}

.stat-value {
  @apply text-sm font-semibold block text-white;
}

.signal-preview {
  @apply mt-2 p-2 bg-blue-900/20 border border-blue-700 rounded text-sm;
}

.signal-type {
  @apply font-bold;
}
</style>
