<template>
  <div class="card">
    <div class="card-header flex items-center justify-between">
      <h2 class="text-xl font-bold">📜 Recent Trades</h2>
      <span v-if="trades.length > 0" class="text-sm text-gray-400">
        Last {{ trades.length }} trades
      </span>
    </div>

    <div class="card-body">
      <div v-if="trades.length === 0" class="text-center text-gray-400 py-8">
        <div class="text-4xl mb-4">R</div>
        <p>No trades yet</p>
      </div>

      <div v-else class="overflow-x-auto">
        <table class="w-full">
          <thead>
            <tr class="text-left text-gray-400 text-sm border-b border-gray-700">
              <th class="pb-3">Time</th>
              <th class="pb-3">Symbol</th>
              <th class="pb-3">Type</th>
              <th class="pb-3">Entry</th>
              <th class="pb-3">Exit</th>
              <th class="pb-3">Confluence</th>
              <th class="pb-3">Status</th>
              <th class="pb-3 text-right">P/L</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="trade in trades"
              :key="trade.id"
              class="border-b border-gray-700/50 hover:bg-gray-700/30 transition-colors"
            >
              <td class="py-3 text-sm">
                {{ new Date(trade.opened_at).toLocaleDateString() }}
                <div class="text-xs text-gray-500">
                  {{ new Date(trade.opened_at).toLocaleTimeString() }}
                </div>
              </td>
              <td class="py-3 font-medium">{{ trade.symbol }}</td>
              <td class="py-3">
                <span
                  class="badge"
                  :class="trade.trade_type === 'BUY' ? 'badge-success' : 'badge-danger'"
                >
                  {{ trade.trade_type }}
                </span>
              </td>
              <td class="py-3 font-mono text-sm">{{ trade.entry_price.toFixed(5) }}</td>
              <td class="py-3 font-mono text-sm">
                {{ trade.exit_price ? trade.exit_price.toFixed(5) : '--' }}
              </td>
              <td class="py-3">
                <div class="flex items-center space-x-2">
                  <span class="font-semibold">{{ trade.confluence_score }}/10</span>
                  <div class="flex-1 h-2 bg-gray-600 rounded-full overflow-hidden" style="max-width: 60px;">
                    <div
                      class="h-full bg-blue-500 rounded-full transition-all"
                      :style="{ width: `${(trade.confluence_score / 10) * 100}%` }"
                    ></div>
                  </div>
                </div>
              </td>
              <td class="py-3">
                <span
                  class="badge"
                  :class="{
                    'badge-success': trade.status === 'CLOSED' && trade.profit_loss > 0,
                    'badge-danger': trade.status === 'CLOSED' && trade.profit_loss < 0,
                    'badge-info': trade.status === 'OPEN',
                    'badge-warning': trade.status === 'CANCELLED'
                  }"
                >
                  {{ trade.status }}
                </span>
              </td>
              <td class="py-3 text-right">
                <div
                  class="font-bold"
                  :class="trade.profit_loss >= 0 ? 'text-green-400' : 'text-red-400'"
                >
                  {{ trade.profit_loss >= 0 ? '+' : '' }}${{ trade.profit_loss.toFixed(2) }}
                </div>
              </td>
            </tr>
          </tbody>
          <tfoot v-if="totalPnL !== 0">
            <tr class="border-t-2 border-gray-600">
              <td colspan="7" class="py-3 text-right font-semibold text-gray-300">
                Total:
              </td>
              <td class="py-3 text-right">
                <div
                  class="text-xl font-bold"
                  :class="totalPnL >= 0 ? 'text-green-400' : 'text-red-400'"
                >
                  {{ totalPnL >= 0 ? '+' : '' }}${{ totalPnL.toFixed(2) }}
                </div>
                <div class="text-xs text-gray-500">
                  Win Rate: {{ winRate.toFixed(1) }}%
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
  trades: {
    type: Array,
    default: () => []
  }
})

const totalPnL = computed(() => {
  return props.trades.reduce((sum, trade) => sum + (trade.profit_loss || 0), 0)
})

const winRate = computed(() => {
  const closedTrades = props.trades.filter(t => t.status === 'CLOSED')
  if (closedTrades.length === 0) return 0

  const winners = closedTrades.filter(t => t.profit_loss > 0).length
  return (winners / closedTrades.length) * 100
})
</script>
