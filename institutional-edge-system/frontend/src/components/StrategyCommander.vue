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
    
    <div class="card-body flex-1 overflow-y-auto space-y-4 custom-scrollbar pr-2">
      <!-- Bot Control Item -->
      <div v-for="bot in bots" :key="bot.id" 
           class="bg-slate-950/50 border border-slate-800 rounded-lg p-4 hover:border-blue-500/30 transition-colors">
        <div class="flex justify-between items-center mb-3">
          <div>
            <div class="font-bold text-white text-lg">{{ bot.name }}</div>
            <div class="text-xs text-slate-400 font-mono flex items-center mt-1">
              {{ bot.symbol }} / 
              <select 
                v-model="bot.timeframe" 
                @change="updateTimeframe(bot)"
                class="ml-1 bg-slate-900 border border-slate-700 rounded px-1 py-0.5 text-xs text-white focus:outline-none focus:border-blue-500"
                :disabled="bot.isLoading"
              >
                <option value="M1">M1</option>
                <option value="M5">M5</option>
                <option value="M15">M15</option>
                <option value="H1">H1</option>
                <option value="H4">H4</option>
                <option value="D1">D1</option>
              </select>
            </div>
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
      
      <div v-if="bots.length === 0" class="text-center text-slate-500 py-4">
        No bots configured.
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
  try {
    const response = await api.getBots()
    bots.value = response.map(bot => ({
      ...bot,
      isLoading: false,
      is_running: false, // Will be updated by status check
      pnl_today: 0,
      total_trades_today: 0
    }))
    
    // Initial status check
    updateAllStatuses()
  } catch (e) {
    console.error("Failed to load bots", e)
  }
}

async function updateAllStatuses() {
  for (const bot of bots.value) {
    try {
      const status = await api.getBotStatus(bot.id)
      Object.assign(bot, status)
    } catch (e) {
      // Silent fail for status updates
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
      // It might take a moment to actually start running, status will be updated by interval
    }
  } catch (e) {
    console.error("Failed to toggle bot", e)
    alert("Failed to toggle bot. Check console.")
  } finally {
    bot.isLoading = false
  }
}

async function updateTimeframe(bot) {
  bot.isLoading = true
  try {
    await api.updateBotConfig(bot.id, { timeframe: bot.timeframe })
    // Status update will happen automatically on next interval
  } catch (e) {
    console.error("Failed to update timeframe", e)
    alert("Failed to update timeframe")
  } finally {
    bot.isLoading = false
  }
}

onMounted(() => {
  loadBots()
  // Refresh status every 5s
  setInterval(updateAllStatuses, 5000)
})
</script>

<style scoped>
.custom-scrollbar::-webkit-scrollbar {
  width: 4px;
}
.custom-scrollbar::-webkit-scrollbar-track {
  background: rgba(0, 0, 0, 0.1);
}
.custom-scrollbar::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.2);
  border-radius: 2px;
}
.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: rgba(255, 255, 255, 0.3);
}
</style>
