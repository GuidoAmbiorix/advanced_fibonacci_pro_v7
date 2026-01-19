<template>
  <div class="relative overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-r from-slate-900/80 via-slate-800/80 to-slate-900/80 backdrop-blur-xl p-5 shadow-xl">
    <div class="flex justify-between items-center mb-4">
      <div class="flex items-center space-x-3">
        <h3 class="text-lg font-bold text-white flex items-center gap-2">
          <span class="text-2xl">🎰</span> 
          <span class="bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">Portfolio Slots</span>
        </h3>
        <button @click="$emit('add-slot')" 
                class="group px-3 py-1.5 bg-gradient-to-r from-emerald-600 to-green-500 hover:from-emerald-500 hover:to-green-400 text-white text-xs font-semibold rounded-lg transition-all shadow-lg shadow-emerald-500/20 hover:shadow-emerald-400/30 hover:scale-105">
          <span class="flex items-center gap-1">
            <span class="group-hover:rotate-90 transition-transform duration-300">➕</span>
            <span>Add Slot</span>
          </span>
        </button>
      </div>
      <div class="flex items-center space-x-3">
        <!-- Capital Input -->
        <div class="flex items-center gap-2 bg-gray-800/60 rounded-xl px-3 py-2 border border-gray-700/50">
          <span class="text-xs text-gray-400">💵 Capital</span>
          <input type="number" v-model.number="sharedConfig.initial_balance" 
                 class="bg-transparent text-sm text-white w-20 focus:outline-none text-right font-mono">
        </div>
        <div class="hidden md:flex items-center gap-3 text-xs text-gray-400">
          <span class="px-2 py-1 bg-gray-800/40 rounded-lg border border-gray-700/30">
            Max Risk: <span class="text-yellow-400 font-semibold">{{ portfolioSynergy.max_risk }}%</span>
          </span>
          <span class="px-2 py-1 bg-gray-800/40 rounded-lg border border-gray-700/30">
            Max/Symbol: <span class="text-cyan-400 font-semibold">{{ portfolioSynergy.max_positions }}</span>
          </span>
        </div>
      </div>
    </div>
    
    <!-- Slot Cards Grid -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <BacktestSlotCard
        v-for="(slot, index) in slots" 
        :key="slot.id"
        v-model="slots[index]"
        @save="$emit('save-slot', $event)"
        @clone="$emit('clone-slot', $event)"
        @delete="$emit('delete-slot', $event)"
        @preset="$emit('apply-preset', $event)"
      />
    </div>
  </div>
</template>

<script setup>
import BacktestSlotCard from './BacktestSlotCard.vue'

defineProps({
  slots: {
    type: Array, 
    required: true
  },
  sharedConfig: {
    type: Object,
    required: true
  },
  portfolioSynergy: {
    type: Object,
    default: () => ({ max_risk: 0, max_positions: 0 })
  }
})

defineEmits(['add-slot', 'save-slot', 'clone-slot', 'delete-slot', 'apply-preset'])
</script>
