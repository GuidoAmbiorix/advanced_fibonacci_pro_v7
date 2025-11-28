<template>
  <div class="card">
    <div class="card-header flex items-center justify-between">
      <h2 class="text-xl font-bold">🎯 Trading Signals</h2>
      <span v-if="signals.length > 0" class="badge badge-success">
        {{ signals.length }} Active
      </span>
    </div>

    <div class="card-body">
      <div v-if="signals.length === 0" class="text-center text-gray-400 py-8">
        <div class="text-4xl mb-4">📭</div>
        <p>No signals detected</p>
        <p class="text-sm mt-2">Waiting for high confluence setups...</p>
      </div>

      <div v-else class="space-y-4">
        <div
          v-for="(signal, index) in signals"
          :key="index"
          class="p-4 rounded-lg border-2"
          :class="signal.signal_type === 'BUY' ? 'bg-green-900/20 border-green-600' : 'bg-red-900/20 border-red-600'"
        >
          <div class="flex items-start justify-between mb-4">
            <div>
              <div class="flex items-center space-x-3">
                <span
                  class="text-2xl font-bold px-4 py-2 rounded"
                  :class="signal.signal_type === 'BUY' ? 'bg-green-600 text-white' : 'bg-red-600 text-white'"
                >
                  {{ signal.signal_type }}
                </span>
                
                <!-- God Mode Badge -->
                <span 
                  v-if="signal.score_breakdown['Trend (EMA)'] && signal.score_breakdown['Momentum (MACD)'] && signal.score_breakdown['Volume (OBV)']"
                  class="bg-yellow-500 text-black font-bold px-2 py-1 rounded text-xs animate-pulse"
                >
                  ⚡ GOD MODE
                </span>

                <div>
                  <div class="text-sm text-gray-400">{{ signal.symbol }} - {{ signal.timeframe }}</div>
                  <div class="text-xs text-gray-500">
                    {{ new Date(signal.timestamp).toLocaleString() }}
                  </div>
                </div>
              </div>
            </div>

            <div class="text-right">
              <div class="text-3xl font-bold">{{ signal.confluence_score }}/10</div>
              <div class="text-xs text-gray-400">Confluence</div>
            </div>
          </div>

          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
            <div>
              <div class="text-xs text-gray-400">Entry Price</div>
              <div class="text-lg font-semibold">{{ signal.entry_price.toFixed(5) }}</div>
            </div>
            <div>
              <div class="text-xs text-gray-400">Stop Loss</div>
              <div class="text-lg font-semibold text-red-400">{{ signal.stop_loss.toFixed(5) }}</div>
            </div>
            <div>
              <div class="text-xs text-gray-400">TP1</div>
              <div class="text-lg font-semibold text-green-400">{{ signal.take_profit_1.toFixed(5) }}</div>
            </div>
            <div>
              <div class="text-xs text-gray-400">TP2</div>
              <div class="text-lg font-semibold text-green-400">{{ signal.take_profit_2.toFixed(5) }}</div>
            </div>
          </div>

          <div class="mb-4">
            <div class="text-sm font-semibold text-gray-300 mb-2">Confluence Factors:</div>
            <div class="flex flex-wrap gap-2">
              <span
                v-for="(score, factor) in signal.score_breakdown"
                :key="factor"
                class="badge badge-info"
              >
                {{ factor }}: +{{ score }}
              </span>
            </div>
          </div>

          <div class="flex justify-end">
            <button
              @click="$emit('execute', signal)"
              class="btn-primary"
            >
              Execute Trade
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
defineProps({
  signals: {
    type: Array,
    default: () => []
  }
})

defineEmits(['execute'])
</script>
