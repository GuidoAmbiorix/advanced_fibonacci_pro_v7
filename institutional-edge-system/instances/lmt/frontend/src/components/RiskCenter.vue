<template>
  <div class="card h-full flex flex-col">
    <div class="card-header">
      <h3 class="text-lg font-bold text-white flex items-center">
        <span class="mr-2">🛡️</span> Risk Center
      </h3>
    </div>
    
    <div class="card-body flex-1 flex flex-col justify-between space-y-4">
      <!-- Risk Gauge (Simplified Visual) -->
      <div class="relative pt-4">
        <div class="flex justify-between text-xs text-slate-400 mb-1">
          <span>Low Risk</span>
          <span>Critical</span>
        </div>
        <div class="h-4 bg-slate-800 rounded-full overflow-hidden flex">
          <div class="w-1/3 bg-emerald-500/50"></div>
          <div class="w-1/3 bg-yellow-500/50"></div>
          <div class="w-1/3 bg-red-500/50"></div>
        </div>
        <!-- Indicator -->
        <div class="absolute top-3 w-1 h-6 bg-white border border-slate-900 shadow-lg transition-all duration-500"
             :style="{ left: `${riskPercentage}%` }"></div>
        <div class="text-center mt-2 font-bold text-xl" :class="riskColor">
          {{ riskPercentage.toFixed(1) }}% Exposure
        </div>
      </div>

      <!-- Metrics Grid -->
      <div class="grid grid-cols-2 gap-4">
        <div class="bg-slate-950/50 p-3 rounded border border-slate-800">
          <div class="text-xs text-slate-500">Margin Level</div>
          <div class="text-lg font-mono font-bold text-white">
            {{ account?.margin_level ? account.margin_level.toFixed(0) : '0' }}%
          </div>
        </div>
        <div class="bg-slate-950/50 p-3 rounded border border-slate-800">
          <div class="text-xs text-slate-500">Daily Drawdown</div>
          <div class="text-lg font-mono font-bold text-white">
            {{ dailyDrawdown.toFixed(2) }}%
          </div>
        </div>
      </div>

      <!-- Alerts -->
      <div v-if="riskPercentage > 80" class="bg-red-500/20 border border-red-500/50 p-3 rounded text-xs text-red-200 flex items-center animate-pulse">
        <span class="mr-2">R</span> CRITICAL RISK LEVEL DETECTED
      </div>
      <div v-else class="bg-emerald-500/10 border border-emerald-500/20 p-3 rounded text-xs text-emerald-400 flex items-center">
        <span class="mr-2">R</span> Risk Parameters Normal
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import api from '../services/api'

const account = ref(null)
const dailyDrawdown = ref(0) // Mock for now, would need historical equity

const riskPercentage = computed(() => {
  if (!account.value || account.value.balance === 0) return 0
  // Simple exposure calc: Used Margin / Balance * 100 (or similar)
  // Or (100 - Margin Level / 100) if Margin Level is huge
  // Let's use Margin / Equity as a proxy for exposure
  if (account.value.equity === 0) return 0
  return (account.value.margin / account.value.equity) * 100
})

const riskColor = computed(() => {
  if (riskPercentage.value < 30) return 'text-emerald-400'
  if (riskPercentage.value < 70) return 'text-yellow-400'
  return 'text-red-400'
})

async function loadData() {
  try {
    account.value = await api.getAccountInfo()
    // Mock daily drawdown for visual
    dailyDrawdown.value = Math.random() * 2 
  } catch (e) {
    console.error("Failed to load account info", e)
  }
}

onMounted(() => {
  loadData()
  setInterval(loadData, 5000)
})
</script>
