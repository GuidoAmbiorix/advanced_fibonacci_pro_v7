<template>
  <div class="bg-gray-800 rounded-lg shadow-lg p-4 h-full flex flex-col">
    <div class="flex justify-between items-center mb-4">
      <h3 class="text-lg font-semibold text-white flex items-center">
        <span class="w-2 h-2 bg-green-500 rounded-full mr-2 animate-pulse"></span>
        Live Activity Log
      </h3>
      <button @click="clearLogs" class="text-xs text-gray-400 hover:text-white transition-colors">
        Clear
      </button>
    </div>

    <div class="flex-1 overflow-y-auto space-y-2 pr-2 custom-scrollbar" ref="logContainer">
      <div 
        v-for="(log, index) in logs" 
        :key="index" 
        class="text-sm p-2 rounded border-l-2 animate-fade-in"
        :class="getLogClass(log.level)"
      >
        <div class="flex justify-between text-xs opacity-70 mb-1">
          <span>{{ formatTime(log.timestamp) }}</span>
          <span class="uppercase font-bold tracking-wider">{{ log.level }}</span>
        </div>
        <div class="font-medium">{{ log.message }}</div>
      </div>
      
      <div v-if="logs.length === 0" class="text-center text-gray-500 py-8 italic">
        Waiting for bot activity...
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, watch, nextTick } from 'vue'
import api from '../services/api'

const logs = ref([])
const logContainer = ref(null)

// Add a new log message
const addLog = (log) => {
  logs.value.unshift(log) // Add to top
  
  // Keep max 100 logs
  if (logs.value.length > 100) {
    logs.value.pop()
  }
}

const getLogClass = (level) => {
  switch (level) {
    case 'error': return 'bg-red-900/20 border-red-500 text-red-200'
    case 'warning': return 'bg-yellow-900/20 border-yellow-500 text-yellow-200'
    case 'success': return 'bg-green-900/20 border-green-500 text-green-200'
    default: return 'bg-gray-700/30 border-blue-500 text-gray-200'
  }
}

const formatTime = (isoString) => {
  if (!isoString) return ''
  return new Date(isoString).toLocaleTimeString()
}

const clearLogs = () => {
  logs.value = []
}

onMounted(() => {
  // Listen for bot activity events
  const socket = api.getSocket()
  if (socket) {
    socket.on('bot_activity', (data) => {
      addLog(data)
    })
  }
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

@keyframes fade-in {
  from { opacity: 0; transform: translateY(-5px); }
  to { opacity: 1; transform: translateY(0); }
}
.animate-fade-in {
  animation: fade-in 0.3s ease-out;
}
</style>
