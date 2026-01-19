<template>
  <div class="bg-gray-800 rounded-xl border border-gray-700 p-4">
    <h3 class="text-sm font-semibold text-gray-300 mb-3">⚠️ Portfolio Risk</h3>
    <div class="space-y-3">
      <div>
        <div class="flex justify-between text-xs mb-1">
          <span class="text-gray-500">Potential Risk</span>
          <span class="text-white">{{ totalPotentialRisk.toFixed(1) }}% / {{ portfolioSynergy.max_risk }}%</span>
        </div>
        <div class="w-full bg-gray-700 rounded-full h-2">
          <div 
            class="h-2 rounded-full transition-all"
            :class="totalPotentialRisk > portfolioSynergy.max_risk ? 'bg-red-500' : totalPotentialRisk > portfolioSynergy.max_risk * 0.8 ? 'bg-yellow-500' : 'bg-green-500'"
            :style="{ width: Math.min(totalPotentialRisk / portfolioSynergy.max_risk * 100, 100) + '%' }"
          ></div>
        </div>
        <div class="text-xs text-gray-600 mt-1">Active: {{ totalActiveRisk.toFixed(1) }}%</div>
      </div>
      <div class="grid grid-cols-2 gap-2 text-xs">
        <div class="bg-gray-900 rounded p-2">
          <div class="text-gray-500">{{ tradingMode === 'live' ? 'Open Positions' : 'Total Trades' }}</div>
          <div class="text-lg font-bold text-white">{{ tradingMode === 'live' ? openPositionCount : metrics.totalTrades }}</div>
        </div>
        <div class="bg-gray-900 rounded p-2">
          <div class="text-gray-500">Active Slots</div>
          <div class="text-lg font-bold text-blue-400">{{ activeSlotCount }}</div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
defineProps({
  totalPotentialRisk: {
    type: Number,
    required: true
  },
  portfolioSynergy: {
    type: Object,
    required: true
  },
  totalActiveRisk: {
    type: Number,
    required: true
  },
  tradingMode: {
    type: String,
    required: true
  },
  openPositionCount: {
    type: Number,
    required: true
  },
  metrics: {
    type: Object,
    required: true
  },
  activeSlotCount: {
    type: Number,
    required: true
  }
})
</script>
