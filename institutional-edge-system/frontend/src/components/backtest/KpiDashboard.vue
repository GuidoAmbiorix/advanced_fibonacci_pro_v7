<template>
  <div v-if="tradingMode === 'backtest'" class="bg-gradient-to-r from-blue-900/40 to-purple-900/40 rounded-xl border border-blue-700 p-4">
    <div class="flex justify-between items-center mb-3">
      <h3 class="font-semibold text-white text-lg">📊 Portfolio Summary</h3>
      <span class="text-xs text-gray-400">Combined results from all {{ slotCount }} slots</span>
    </div>
    <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
      <!-- Total Net Profit -->
      <div class="bg-gray-800/60 rounded-lg p-3 text-center">
        <div class="text-xs text-gray-500 mb-1">💰 Net Profit</div>
        <div class="text-xl font-bold" :class="metrics.netProfit >= 0 ? 'text-green-400' : 'text-red-400'">
          {{ metrics.netProfit >= 0 ? '+' : '' }}${{ metrics.netProfit.toFixed(0) }}
        </div>
      </div>
      <!-- Combined Win Rate -->
      <div class="bg-gray-800/60 rounded-lg p-3 text-center">
        <div class="text-xs text-gray-500 mb-1">🎯 Win Rate</div>
        <div class="text-xl font-bold" :class="metrics.winRate >= 50 ? 'text-green-400' : 'text-yellow-400'">
          {{ metrics.winRate.toFixed(1) }}%
        </div>
      </div>
      <!-- Max Drawdown -->
      <div class="bg-gray-800/60 rounded-lg p-3 text-center">
        <div class="text-xs text-gray-500 mb-1">📉 Max DD</div>
        <div class="text-xl font-bold text-red-400">{{ metrics.maxDrawdown.toFixed(1) }}%</div>
      </div>
      <!-- Total Trades -->
      <div class="bg-gray-800/60 rounded-lg p-3 text-center">
        <div class="text-xs text-gray-500 mb-1">📈 Total Trades</div>
        <div class="text-xl font-bold text-white">{{ metrics.totalTrades }}</div>
      </div>
      <!-- Average Profit Factor -->
      <div class="bg-gray-800/60 rounded-lg p-3 text-center">
        <div class="text-xs text-gray-500 mb-1">⚖️ Profit Factor</div>
        <div class="text-xl font-bold" :class="metrics.profitFactor >= 1.5 ? 'text-green-400' : 'text-yellow-400'">
          {{ metrics.profitFactor.toFixed(2) }}
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
defineProps({
  metrics: {
    type: Object,
    required: true,
    default: () => ({
      netProfit: 0,
      winRate: 0,
      maxDrawdown: 0,
      totalTrades: 0,
      profitFactor: 0
    })
  },
  tradingMode: {
    type: String,
    default: 'backtest'
  },
  slotCount: {
    type: Number,
    default: 0
  }
})
</script>
