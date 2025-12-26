
<template>
  <div class="mini-slot-card h-full flex flex-col bg-gray-900 border border-gray-700 rounded-lg overflow-hidden relative group">
    <!-- Header -->
    <div class="px-2 py-1 bg-gray-800 flex justify-between items-center text-xs">
        <span class="font-bold text-white">{{ slotData.symbol }} ({{ slotData.timeframe }})</span>
        <button @click="$emit('expand', slotData.id)" class="hover:text-blue-400">
            <ArrowsPointingOutIcon class="w-4 h-4" />
        </button>
    </div>
    
    <!-- Chart Area -->
    <!-- Chart Area -->
    <div class="flex-1 relative">
        <UnifiedTradingChart 
            :slot-data="slotData" 
            mode="LIVE" 
            class="w-full h-full"
        />
        <!-- Overlay for click-to-expand if needed -->
    </div>
  </div>
</template>

<script setup>
import UnifiedTradingChart from './UnifiedTradingChart.vue'
import { ArrowsPointingOutIcon } from '@heroicons/vue/24/outline'

const props = defineProps({
  slotData: {
    type: Object,
    required: true
  }
})

defineEmits(['expand'])
</script>

<style scoped>
.mini-slot-card {
  height: 500px;
}
</style>
