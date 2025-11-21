<template>
  <div class="card">
    <div class="card-header flex items-center justify-between">
      <h2 class="text-xl font-bold">📊 Open Positions</h2>
      <div class="flex items-center space-x-2">
        <span v-if="positions.length > 0" class="badge badge-info">
          {{ positions.length }} Open
        </span>
        <button @click="$emit('refresh')" class="btn-secondary text-sm py-1 px-3">
          🔄 Refresh
        </button>
      </div>
    </div>

    <div class="card-body">
      <div v-if="positions.length === 0" class="text-center text-gray-400 py-8">
        <div class="text-4xl mb-4">💼</div>
        <p>No open positions</p>
      </div>

      <div v-else class="overflow-x-auto">
        <table class="w-full">
          <thead>
            <tr class="text-left text-gray-400 text-sm border-b border-gray-700">
              <th class="pb-3">Ticket</th>
              <th class="pb-3">Symbol</th>
              <th class="pb-3">Type</th>
              <th class="pb-3">Volume</th>
              <th class="pb-3">Entry</th>
              <th class="pb-3">Current</th>
              <th class="pb-3">SL</th>
              <th class="pb-3">TP</th>
              <th class="pb-3 text-right">P/L</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="pos in positions"
              :key="pos.ticket"
              class="border-b border-gray-700/50 hover:bg-gray-700/30 transition-colors"
            >
              <td class="py-3 font-mono text-sm">{{ pos.ticket }}</td>
              <td class="py-3 font-medium">{{ pos.symbol }}</td>
              <td class="py-3">
                <span
                  class="badge"
                  :class="pos.type === 'BUY' ? 'badge-success' : 'badge-danger'"
                >
                  {{ pos.type }}
                </span>
              </td>
              <td class="py-3">{{ pos.volume }}</td>
              <td class="py-3 font-mono text-sm">{{ pos.price_open.toFixed(5) }}</td>
              <td class="py-3 font-mono text-sm">{{ pos.price_current.toFixed(5) }}</td>
              <td class="py-3 font-mono text-sm text-red-400">
                {{ pos.sl ? pos.sl.toFixed(5) : '--' }}
              </td>
              <td class="py-3 font-mono text-sm text-green-400">
                {{ pos.tp ? pos.tp.toFixed(5) : '--' }}
              </td>
              <td class="py-3 text-right">
                <div
                  class="font-bold"
                  :class="pos.profit >= 0 ? 'text-green-400' : 'text-red-400'"
                >
                  {{ pos.profit >= 0 ? '+' : '' }}${{ pos.profit.toFixed(2) }}
                </div>
                <div class="text-xs text-gray-500">
                  {{ Math.abs(pos.price_current - pos.price_open).toFixed(5) }} pips
                </div>
              </td>
            </tr>
          </tbody>
          <tfoot v-if="totalPnL !== 0">
            <tr class="border-t-2 border-gray-600">
              <td colspan="8" class="py-3 text-right font-semibold text-gray-300">
                Total P/L:
              </td>
              <td class="py-3 text-right">
                <div
                  class="text-xl font-bold"
                  :class="totalPnL >= 0 ? 'text-green-400' : 'text-red-400'"
                >
                  {{ totalPnL >= 0 ? '+' : '' }}${{ totalPnL.toFixed(2) }}
                </div>
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  positions: {
    type: Array,
    default: () => []
  }
})

defineEmits(['refresh'])

const totalPnL = computed(() => {
  return props.positions.reduce((sum, pos) => sum + (pos.profit || 0), 0)
})
</script>
