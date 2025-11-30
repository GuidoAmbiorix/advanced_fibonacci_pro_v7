        <div class="text-6xl mb-4 opacity-50">📭</div>
        <p class="text-lg">No signals detected</p>
        <p class="text-sm mt-2 text-gray-500">Waiting for high confluence setups...</p>
      </div>

      <div v-else class="space-y-4">
        <div
          v-for="(signal, index) in signals"
          :key="index"
          class="p-4 rounded-xl border transition-all duration-300 hover:scale-[1.02]"
          :class="signal.signal_type === 'BUY' 
            ? 'bg-gradient-to-r from-green-900/20 to-transparent border-green-500/30 hover:shadow-[0_0_15px_rgba(16,185,129,0.2)]' 
            : 'bg-gradient-to-r from-red-900/20 to-transparent border-red-500/30 hover:shadow-[0_0_15px_rgba(239,68,68,0.2)]'"
        >
          <div class="flex items-start justify-between mb-4">
            <div>
              <div class="flex items-center space-x-3">
                <span
                  class="text-xl font-bold px-4 py-1 rounded-lg shadow-lg backdrop-blur-sm"
                  :class="signal.signal_type === 'BUY' ? 'bg-green-600/80 text-white' : 'bg-red-600/80 text-white'"
                >
                  {{ signal.signal_type }}
                </span>
                
                <!-- God Mode Badge -->
                <span 
                  v-if="signal.score_breakdown['Trend (EMA)'] && signal.score_breakdown['Momentum (MACD)'] && signal.score_breakdown['Volume (OBV)']"
                  class="bg-yellow-500/20 text-yellow-300 border border-yellow-500/50 font-bold px-2 py-1 rounded text-xs animate-pulse shadow-[0_0_10px_rgba(234,179,8,0.3)]"
                >
                  ⚡ GOD MODE
                </span>

                <div>
                  <div class="text-sm font-bold text-gray-200">{{ signal.symbol }}</div>
                  <div class="text-xs text-gray-500">{{ signal.timeframe }} • {{ new Date(signal.timestamp).toLocaleTimeString() }}</div>
                </div>
              </div>
            </div>

            <div class="text-right">
              <div class="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-b from-white to-gray-400">
                {{ signal.confluence_score }}<span class="text-lg text-gray-600">/10</span>
              </div>
              <div class="text-xs text-gray-500 uppercase tracking-wider">Confluence</div>
            </div>
          </div>

          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4 bg-black/20 p-3 rounded-lg">
            <div>
              <div class="text-xs text-gray-500 uppercase">Entry</div>
              <div class="text-lg font-mono text-white">{{ signal.entry_price.toFixed(5) }}</div>
            </div>
            <div>
              <div class="text-xs text-gray-500 uppercase">Stop Loss</div>
              <div class="text-lg font-mono text-red-400">{{ signal.stop_loss.toFixed(5) }}</div>
            </div>
            <div>
              <div class="text-xs text-gray-500 uppercase">TP1</div>
              <div class="text-lg font-mono text-green-400">{{ signal.take_profit_1.toFixed(5) }}</div>
            </div>
            <div>
              <div class="text-xs text-gray-500 uppercase">TP2</div>
              <div class="text-lg font-mono text-green-400">{{ signal.take_profit_2.toFixed(5) }}</div>
            </div>
          </div>

          <div class="mb-4">
            <div class="text-xs font-bold text-gray-400 mb-2 uppercase tracking-wider">Confluence Factors</div>
            <div class="flex flex-wrap gap-2">
              <span
                v-for="(score, factor) in signal.score_breakdown"
                :key="factor"
                class="badge badge-info backdrop-blur-md"
              >
                {{ factor }}: +{{ score }}
              </span>
            </div>
          </div>

          <div class="flex justify-end">
            <button
              @click="$emit('execute', signal)"
              class="btn-primary w-full md:w-auto"
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
