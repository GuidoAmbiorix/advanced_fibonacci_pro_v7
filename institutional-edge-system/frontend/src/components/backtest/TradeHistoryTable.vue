<template>
  <div class="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
    <div class="p-4 border-b border-gray-700 flex justify-between items-center">
      <h3 class="font-semibold text-white">📋 All Trades</h3>
      <span class="text-xs text-gray-500">{{ trades.length }} total</span>
    </div>
    <div class="overflow-x-auto max-h-64">
      <table class="w-full text-left text-sm">
        <thead class="bg-gray-900 text-gray-400 sticky top-0">
          <tr>
            <th class="px-3 py-2">Symbol</th>
            <th class="px-3 py-2">Time</th>
            <th class="px-3 py-2">Duration</th>
            <th class="px-3 py-2">Type</th>
            <th class="px-3 py-2 text-right">Profit</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-700">
          <tr v-if="trades.length === 0">
            <td colspan="5" class="px-4 py-6 text-center text-gray-500">No trades yet</td>
          </tr>
          <tr v-for="trade in trades.slice(0, 50)" :key="trade.id" class="hover:bg-gray-750">
            <td class="px-3 py-2 text-gray-300 text-xs">{{ trade.symbol || '-' }}</td>
            <td class="px-3 py-2 text-gray-400 text-xs">{{ formatDateTime(trade.exit_time) }}</td>
            <td class="px-3 py-2 text-xs">
              <span :class="getDurationColor(trade.entry_time, trade.exit_time)">
                {{ formatDuration(trade.entry_time, trade.exit_time) }}
              </span>
            </td>
            <td class="px-3 py-2">
              <span class="px-2 py-0.5 rounded text-xs font-medium"
                    :class="trade.trade_type === 'BUY' ? 'bg-green-900 text-green-400' : 'bg-red-900 text-red-400'">
                {{ trade.trade_type }}
              </span>
            </td>
            <td class="px-3 py-2 text-right font-medium" :class="trade.profit >= 0 ? 'text-green-400' : 'text-red-400'">
              {{ trade.profit >= 0 ? '+' : '' }}${{ trade.profit?.toFixed(2) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup>
const props = defineProps({
  trades: {
    type: Array,
    required: true
  }
})

// Helper methods for formatting
const formatDateTime = (dateStr) => {
  if (!dateStr) return '-'
  const d = new Date(dateStr)
  return `${d.getMonth()+1}/${d.getDate()} ${d.getHours().toString().padStart(2,'0')}:${d.getMinutes().toString().padStart(2,'0')}`
}

const formatDuration = (startStr, endStr) => {
  if (!startStr || !endStr) return '-'
  const start = new Date(startStr)
  const end = new Date(endStr)
  const diffMs = end - start
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMins / 60)
  const diffDays = Math.floor(diffHours / 24)
  
  if (diffDays > 0) return `${diffDays}d ${diffHours % 24}h`
  if (diffHours > 0) return `${diffHours}h ${diffMins % 60}m`
  return `${diffMins}m`
}

const getDurationColor = (start, end) => {
  if (!start || !end) return 'text-gray-500'
  const diffHours = (new Date(end) - new Date(start)) / 3600000
  if (diffHours < 1) return 'text-green-400' // Scalp
  if (diffHours < 4) return 'text-blue-400' // Intraday
  return 'text-purple-400' // Swing
}
</script>
