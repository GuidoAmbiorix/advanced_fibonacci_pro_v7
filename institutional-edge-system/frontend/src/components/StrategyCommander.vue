<template>
  <div class="card h-full flex flex-col">
    <div class="card-header flex justify-between items-center">
      <h3 class="text-lg font-bold text-white flex items-center">
        <span class="mr-2">⚡</span> Strategy Commander
      </h3>
      <div class="flex space-x-2">
        <span class="w-2 h-2 rounded-full animate-pulse" 
              :class="isSystemActive ? 'bg-emerald-500' : 'bg-red-500'"></span>
      </div>
    </div>
    
    <div class="card-body flex-1 overflow-y-auto space-y-4">
      <!-- Bot Control Item -->
      <div v-for="bot in bots" :key="bot.id" 
           class="bg-slate-950/50 border border-slate-800 rounded-lg p-4 hover:border-blue-500/30 transition-colors">
        <div class="flex justify-between items-center mb-3">
          <div>
            <div class="font-bold text-white text-lg">{{ bot.name }}</div>
            <div class="text-xs text-slate-400 font-mono">{{ bot.symbol }} / {{ bot.timeframe }}</div>
          </div>
          <label class="relative inline-flex items-center cursor-pointer">
            <input type="checkbox" class="sr-only peer" 
                   :checked="bot.is_active" 
                   @change="toggleBot(bot)"
                   :disabled="bot.isLoading">
            <div class="w-11 h-6 bg-slate-700 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-800 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
          </label>
        </div>
        
        <div class="grid grid-cols-3 gap-2 text-xs">
          <div class="bg-slate-900 p-2 rounded text-center">
            <div class="text-slate-500 mb-1">PnL Today</div>
            <div :class="bot.pnl_today >= 0 ? 'text-emerald-400' : 'text-red-400'" class="font-bold">
              ${{ bot.pnl_today?.toFixed(2) || '0.00' }}
            </div>
          </div>
          <div class="bg-slate-900 p-2 rounded text-center">
            <div class="text-slate-500 mb-1">Trades</div>
            <div class="text-white font-bold">{{ bot.total_trades_today || 0 }}</div>
          </div>
          <div class="bg-slate-900 p-2 rounded text-center">
            <div class="text-slate-500 mb-1">Status</div>
            <div :class="bot.is_running ? 'text-emerald-400' : 'text-slate-400'" class="font-bold">
              {{ bot.is_running ? 'RUNNING' : 'IDLE' }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue'
import api from '../services/api'

const bots = ref([])
const isSystemActive = computed(() => bots.value.some(b => b.is_running))

async function loadBots() {
  // For now, we'll mock the list or fetch if endpoint exists. 
  // Assuming we have a way to get list of bots. 
  // If not, we'll hardcode the known ones for this phase.
  
  // TODO: Implement getBots endpoint in backend if not exists
  // For now, using mock structure that we'll hydrate with status
  bots.value = [
    { id: 1, name: 'Bitcoin Alpha', symbol: 'BTCUSD', timeframe: 'H1', is_active: false, is_running: false, pnl_today: 0, total_trades_today: 0, isLoading: false },
    { id: 2, name: 'Euro Sniper', symbol: 'EURUSD', timeframe: 'H1', is_active: false, is_running: false, pnl_today: 0, total_trades_today: 0, isLoading: false }
  ]
  
  // Hydrate with real status
  for (const bot of bots.value) {
    try {
      const status = await api.getBotStatus(bot.id)
      Object.assign(bot, status)
    } catch (e) {
      console.error(`Failed to load status for bot ${bot.id}`, e)
    }
  }
}

async function toggleBot(bot) {
  bot.isLoading = true
  try {
    if (bot.is_active) {
      await api.stopBot(bot.id)
      bot.is_active = false
      bot.is_running = false
    } else {
      await api.startBot(bot.id)
      bot.is_active = true
      // It might take a moment to actually start running
      setTimeout(async () => {
         const status = await api.getBotStatus(bot.id)
         bot.is_running = status.is_running
      }, 1000)
    }
  } catch (e) {
    console.error("Failed to toggle bot", e)
    alert("Failed to toggle bot. Check console.")
  } finally {
    bot.isLoading = false
  }
}

onMounted(() => {
  loadBots()
  // Refresh status every 5s
  setInterval(async () => {
    for (const bot of bots.value) {
      if (bot.is_active) {
        try {
          const status = await api.getBotStatus(bot.id)
          Object.assign(bot, status)
        } catch (e) {}
      }
    }
  }, 5000)
})
</script>
