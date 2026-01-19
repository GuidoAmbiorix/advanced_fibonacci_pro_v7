<template>
  <div class="bg-gradient-to-br from-slate-900 to-gray-900 rounded-xl border border-gray-700/50 shadow-xl overflow-hidden">
    <!-- Header -->
    <div class="px-4 py-3 border-b border-gray-700/50 flex items-center justify-between bg-gradient-to-r from-gray-800/50 to-slate-800/50">
      <div class="flex items-center gap-3">
        <button @click="expanded = !expanded" class="text-gray-400 hover:text-white transition-colors">
          <svg class="w-5 h-5 transition-transform" :class="expanded ? 'rotate-180' : ''" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
          </svg>
        </button>
        <h3 class="text-sm font-bold text-white flex items-center gap-2">
          🖥️ System Logs
          <span class="text-xs text-gray-500 font-normal">(Backend Output)</span>
        </h3>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-xs text-gray-500">{{ logs.length }} entries</span>
        <div class="flex items-center gap-1.5 px-2 py-1 rounded-full text-xs"
             :class="isConnected ? 'bg-green-500/10 text-green-400 border border-green-500/30' : 'bg-red-500/10 text-red-400 border border-red-500/30'">
          <span class="w-1.5 h-1.5 rounded-full" :class="isConnected ? 'bg-green-400' : 'bg-red-400'"></span>
          {{ isConnected ? 'Live' : 'Offline' }}
        </div>
      </div>
    </div>

    <!-- Terminal Window (Collapsible) -->
    <div v-show="expanded" class="font-mono text-xs">
      <!-- Toolbar -->
      <div class="flex items-center justify-between px-4 py-2 bg-[#0f111a] border-b border-gray-800">
        <div class="flex space-x-2">
          <div class="w-3 h-3 rounded-full bg-red-500/50"></div>
          <div class="w-3 h-3 rounded-full bg-yellow-500/50"></div>
          <div class="w-3 h-3 rounded-full bg-green-500/50"></div>
        </div>
        <div class="flex items-center gap-4">
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="checkbox" v-model="autoScroll" class="w-3 h-3 rounded bg-gray-700 border-gray-600 text-blue-500">
            <span class="text-gray-400 text-[10px]">Auto-scroll</span>
          </label>
          <input v-model="searchQuery" type="text" placeholder="grep..."
                 class="bg-gray-900 border border-gray-700 rounded px-2 py-1 text-gray-300 text-[10px] focus:outline-none focus:border-blue-500 w-32">
          <button @click="clearLogs" class="text-gray-500 hover:text-red-400 text-[10px] transition-colors">Clear</button>
        </div>
      </div>

      <!-- Logs container -->
      <div ref="logsContainer" class="h-64 overflow-y-auto p-3 space-y-0.5 bg-[#0f111a]">
        <div v-if="filteredLogs.length === 0" class="text-gray-600 italic text-center py-8">
          No logs to display...
        </div>
        
        <div v-for="(log, index) in filteredLogs" :key="index"
             class="flex gap-2 hover:bg-white/5 px-1 py-0.5 rounded transition-colors">
          <!-- Timestamp -->
          <span class="text-gray-500 shrink-0 w-20 select-none">{{ formatTime(log.timestamp) }}</span>
          
          <!-- Level -->
          <span class="font-bold shrink-0 w-14 text-center select-none" :class="getLevelColor(log.level)">
            {{ log.level }}
          </span>
          
          <!-- Module -->
          <span class="text-indigo-400 shrink-0 w-20 truncate select-none" :title="log.module">
            {{ log.module }}
          </span>
          
          <!-- Message -->
          <span class="text-gray-300 break-all whitespace-pre-wrap flex-1 border-l border-gray-800 pl-2">
            {{ log.message }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue'
import axios from 'axios'
import socket from '@/services/socket'

const logs = ref([])
const autoScroll = ref(true)
const searchQuery = ref('')
const logsContainer = ref(null)
const isConnected = ref(false)
const expanded = ref(true)

// Fetch initial history
const fetchHistory = async () => {
  try {
    const response = await axios.get('/api/logs/system')
    logs.value = response.data
    scrollToBottom()
  } catch (error) {
    console.error('Failed to fetch system logs:', error)
  }
}

// Scroll helper
const scrollToBottom = () => {
  if (autoScroll.value && logsContainer.value) {
    nextTick(() => {
      logsContainer.value.scrollTop = logsContainer.value.scrollHeight
    })
  }
}

// Colors
const getLevelColor = (level) => {
  switch (level) {
    case 'INFO': return 'text-green-400'
    case 'WARNING': return 'text-yellow-400'
    case 'ERROR': return 'text-red-500 bg-red-900/10'
    case 'CRITICAL': return 'text-red-600 font-black bg-red-900/20'
    case 'DEBUG': return 'text-blue-400'
    default: return 'text-gray-400'
  }
}

const formatTime = (iso) => {
  if (!iso) return ''
  return new Date(iso).toLocaleTimeString('en-US', { 
    hour12: false, 
    hour: '2-digit', 
    minute: '2-digit', 
    second: '2-digit' 
  })
}

const clearLogs = () => {
  logs.value = []
}

const filteredLogs = computed(() => {
  if (!searchQuery.value) return logs.value
  const lower = searchQuery.value.toLowerCase()
  return logs.value.filter(l => 
    l.message?.toLowerCase().includes(lower) || 
    l.module?.toLowerCase().includes(lower)
  )
})

// Socket Handlers
const onLog = (logEntry) => {
  logs.value.push(logEntry)
  if (logs.value.length > 500) logs.value.shift() // Keep last 500
  scrollToBottom()
}

onMounted(() => {
  fetchHistory()
  
  if (socket.connected) isConnected.value = true
  
  socket.on('connect', () => { isConnected.value = true })
  socket.on('disconnect', () => { isConnected.value = false })
  socket.on('system_log', onLog)
})

onUnmounted(() => {
  socket.off('system_log', onLog)
  socket.off('connect')
  socket.off('disconnect')
})
</script>
