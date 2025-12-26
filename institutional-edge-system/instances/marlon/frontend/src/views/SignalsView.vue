<template>
  <div class="space-y-6">
    <div class="flex items-center justify-between">
      <h2 class="text-2xl font-bold text-primary">Trading Signals</h2>
      <div class="flex space-x-2">
        <button class="px-3 py-1 text-sm bg-white border border-slate-200 rounded hover:bg-slate-50">Filter</button>
        <button class="px-3 py-1 text-sm bg-white border border-slate-200 rounded hover:bg-slate-50">Export</button>
      </div>
    </div>

    <!-- Signals List -->
    <div class="bg-white rounded-lg shadow-card overflow-hidden">
      <table class="w-full text-left border-collapse">
        <thead>
          <tr class="bg-slate-50 border-b border-slate-200 text-xs uppercase text-slate-500 font-semibold">
            <th class="px-6 py-4">Time</th>
            <th class="px-6 py-4">Symbol</th>
            <th class="px-6 py-4">Type</th>
            <th class="px-6 py-4">Price</th>
            <th class="px-6 py-4">SL / TP</th>
            <th class="px-6 py-4">Score</th>
            <th class="px-6 py-4">Status</th>
            <th class="px-6 py-4">Action</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="signal in signals" :key="signal.id" class="hover:bg-slate-50 transition-colors">
            <td class="px-6 py-4 text-sm text-slate-500">{{ formatDate(signal.created_at) }}</td>
            <td class="px-6 py-4 font-bold text-primary">{{ signal.symbol }} <span class="text-xs font-normal text-slate-400 ml-1">{{ signal.timeframe }}</span></td>
            <td class="px-6 py-4">
              <span class="px-2 py-1 rounded text-xs font-bold" 
                :class="signal.signal_type === 'BUY' ? 'bg-success/10 text-success' : 'bg-danger/10 text-danger'">
                {{ signal.signal_type }}
              </span>
            </td>
            <td class="px-6 py-4 text-sm font-mono">{{ signal.price }}</td>
            <td class="px-6 py-4 text-xs font-mono text-slate-500">
              <div>SL: {{ signal.stop_loss }}</div>
              <div>TP: {{ signal.take_profit }}</div>
            </td>
            <td class="px-6 py-4">
              <div class="flex items-center space-x-1">
                <div class="w-16 h-2 bg-slate-100 rounded-full overflow-hidden">
                  <div class="h-full bg-accent" :style="{ width: (signal.confluence_score * 10) + '%' }"></div>
                </div>
                <span class="text-xs font-bold text-accent">{{ signal.confluence_score }}/10</span>
              </div>
            </td>
            <td class="px-6 py-4">
              <span v-if="signal.was_executed" class="text-xs font-bold text-slate-400">EXECUTED</span>
              <span v-else class="text-xs font-bold text-accent">PENDING</span>
            </td>
            <td class="px-6 py-4">
              <button v-if="!signal.was_executed" class="px-3 py-1 text-xs font-bold bg-primary text-white rounded hover:bg-primary/90">
                Execute
              </button>
            </td>
          </tr>
          <tr v-if="signals.length === 0">
            <td colspan="8" class="px-6 py-12 text-center text-slate-400">
              No signals found.
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const signals = ref([])

function formatDate(dateString) {
  if (!dateString) return ''
  return new Date(dateString).toLocaleString()
}

async function loadSignals() {
  try {
    const response = await api.getSignals()
    signals.value = response.signals
  } catch (e) {
    console.error("Failed to load signals", e)
    // Mock data for demo
    signals.value = [
      { id: 1, created_at: new Date().toISOString(), symbol: 'EURUSD', timeframe: 'H1', signal_type: 'BUY', price: 1.0850, stop_loss: 1.0820, take_profit: 1.0910, confluence_score: 8, was_executed: false },
      { id: 2, created_at: new Date(Date.now() - 3600000).toISOString(), symbol: 'GBPUSD', timeframe: 'H1', signal_type: 'SELL', price: 1.2650, stop_loss: 1.2680, take_profit: 1.2590, confluence_score: 7, was_executed: true },
    ]
  }
}

onMounted(() => {
  loadSignals()
  
  const socket = api.getSocket()
  if (socket) {
    socket.on('signal_generated', (signal) => {
      signals.value.unshift({
        ...signal,
        id: Date.now(), // Temp ID until refresh
        was_executed: false
      })
      if (signals.value.length > 50) signals.value.pop()
    })
    
    socket.on('signals_cleared', () => {
      signals.value = []
    })
  }
})
</script>
