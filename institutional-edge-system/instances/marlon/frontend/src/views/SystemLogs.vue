<template>
  <div class="p-6 max-w-[1600px] mx-auto">
    <!-- Header -->
    <div class="flex justify-between items-center mb-6">
      <div>
        <h1 class="text-2xl font-bold text-white mb-1">System Logs</h1>
        <p class="text-gray-400 text-sm">Real-time backend system output and debugging</p>
      </div>
      <div class="flex space-x-3">
        <button 
          @click="clearLogs" 
          class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded text-sm transition-colors text-gray-300"
        >
          Clear Terminal
        </button>
        <div class="flex items-center space-x-2 bg-gray-800 rounded px-3 py-2 border border-gray-700">
           <span class="w-2 h-2 rounded-full" :class="isConnected ? 'bg-green-500' : 'bg-red-500'"></span>
           <span class="text-xs text-gray-400">{{ isConnected ? 'Live Stream' : 'Disconnected' }}</span>
        </div>
      </div>
    </div>

    <!-- Terminal Window -->
    <div class="bg-[#0f111a] rounded-lg border border-gray-800 shadow-xl overflow-hidden font-mono text-xs md:text-sm">
       <!-- Toolbar -->
       <div class="flex items-center justify-between px-4 py-2 bg-[#1a1d26] border-b border-gray-800">
          <div class="flex space-x-2">
             <div class="w-3 h-3 rounded-full bg-red-500/50"></div>
             <div class="w-3 h-3 rounded-full bg-yellow-500/50"></div>
             <div class="w-3 h-3 rounded-full bg-green-500/50"></div>
          </div>
          <div class="flex items-center space-x-4">
             <label class="flex items-center space-x-2 cursor-pointer">
                <input type="checkbox" v-model="autoScroll" class="form-checkbox h-3 w-3 text-blue-500 bg-gray-700 border-gray-600 rounded focus:ring-blue-500">
                <span class="text-gray-400 text-xs">Auto-scroll</span>
             </label>
             <input 
                v-model="searchQuery" 
                type="text" 
                placeholder="grep..." 
                class="bg-gray-900 border border-gray-700 rounded px-2 py-1 text-gray-300 text-xs focus:outline-none focus:border-blue-500 w-40"
             >
          </div>
       </div>

       <!-- Logs container -->
       <div 
         ref="logsContainer" 
         class="h-[70vh] overflow-y-auto p-4 space-y-1"
       >
          <div v-if="filteredLogs.length === 0" class="text-gray-600 italic text-center py-20">
             No logs to display...
          </div>
          
          <div 
             v-for="(log, index) in filteredLogs" 
             :key="index" 
             class="flex space-x-3 hover:bg-white/5 p-0.5 rounded transition-colors group"
          >
             <!-- Timestamp -->
             <span class="text-gray-500 shrink-0 select-none w-32">{{ formatTime(log.timestamp) }}</span>
             
             <!-- Level -->
             <span 
                class="font-bold shrink-0 w-16 text-center select-none"
                :class="getLevelColor(log.level)"
             >
                {{ log.level }}
             </span>
             
             <!-- Module -->
             <span class="text-indigo-400 shrink-0 w-24 truncate hidden md:block select-none py-0.5" :title="log.module">
                 {{ log.module }}
             </span>
             
             <!-- Message -->
             <span class="text-gray-300 break-all whitespace-pre-wrap flex-1 border-l border-gray-800 pl-3">
                 {{ log.message }}
             </span>
          </div>
       </div>
    </div>
  </div>
</template>

<script>
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue'
import axios from 'axios'
import socket from '@/services/socket' // Corrected path and default import

export default {
  name: 'SystemLogs',
  setup() {
    const logs = ref([])
    const autoScroll = ref(true)
    const searchQuery = ref('')
    const logsContainer = ref(null)
    const isConnected = ref(false)

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
      return new Date(iso).toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit', fractionalSecondDigits: 3 })
    }

    const clearLogs = () => {
      logs.value = []
    }

    const filteredLogs = computed(() => {
      if (!searchQuery.value) return logs.value
      const lower = searchQuery.value.toLowerCase()
      return logs.value.filter(l => 
         l.message.toLowerCase().includes(lower) || 
         l.module.toLowerCase().includes(lower)
      )
    })

    // Socket Handlers
    const onLog = (logEntry) => {
      logs.value.push(logEntry)
      if (logs.value.length > 2000) logs.value.shift() // Client-side limit
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
    })

    return {
      logs,
      autoScroll,
      searchQuery,
      logsContainer,
      isConnected,
      filteredLogs,
      getLevelColor,
      formatTime,
      clearLogs
    }
  }
}
</script>
