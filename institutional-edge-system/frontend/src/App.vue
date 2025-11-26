<template>
  <div class="min-h-screen bg-gray-900">
    <!-- Header (Only show if not in stream mode) -->
    <header v-if="!isStreamMode" class="bg-slate-950 border-b border-slate-800">
      <div class="max-w-7xl mx-auto px-4 py-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-4">
            <h1 class="text-2xl font-black tracking-tighter text-white">
              QUANTUM <span class="text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-emerald-400">EDGE</span>
            </h1>
            <span class="px-2 py-0.5 rounded text-xs font-bold bg-blue-500/10 text-blue-400 border border-blue-500/20">PRO v2.0</span>
          </div>

          <div class="flex items-center space-x-4">
            <!-- Privacy Toggle -->
            <button @click="togglePrivacy" 
                    class="px-3 py-1 rounded text-xs font-bold transition-colors"
                    :class="privacyMode ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/50' : 'bg-gray-700 text-gray-400 border border-gray-600'">
              {{ privacyMode ? 'PRIVACY ON' : 'PRIVACY OFF' }}
            </button>

            <!-- Stream Mode Link -->
            <router-link to="/stream" class="text-gray-400 hover:text-white transition-colors" title="Open Stream Dashboard">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 10.5l4.72-4.72a.75.75 0 011.28.53v11.38a.75.75 0 01-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 002.25-2.25v-9a2.25 2.25 0 00-2.25-2.25h-9A2.25 2.25 0 002.25 7.5v9a2.25 2.25 0 002.25 2.25z" />
              </svg>
            </router-link>

            <!-- Connection Status -->
            <div class="flex items-center space-x-2">
              <div :class="connectionStatus.color" class="w-3 h-3 rounded-full"></div>
              <span class="text-sm text-gray-400">{{ connectionStatus.text }}</span>
            </div>

            <!-- Account Balance -->
            <div v-if="accountInfo" class="text-sm">
              <span class="text-gray-400">Balance:</span>
              <span class="text-white font-semibold ml-2">
                <span v-if="privacyMode">****</span>
                <span v-else>${{ accountInfo.balance?.toFixed(2) || '0.00' }}</span>
              </span>
            </div>
          </div>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main :class="{'max-w-7xl mx-auto px-4 py-6': !isStreamMode}">
      <router-view :privacy-mode="privacyMode"></router-view>
    </main>

    <!-- Footer (Only show if not in stream mode) -->
    <footer v-if="!isStreamMode" class="bg-gray-800 border-t border-gray-700 mt-12">
      <div class="max-w-7xl mx-auto px-4 py-4 text-center text-gray-400 text-sm">
        <p>© 2024 Institutional Edge PRO. Professional Trading System.</p>
      </div>
    </footer>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import api from './services/api'

const route = useRoute()
const accountInfo = ref(null)
const isConnected = ref(false)
const ws = ref(null)
const privacyMode = ref(false)

const isStreamMode = computed(() => route.path === '/stream')

const connectionStatus = computed(() => {
  if (isConnected.value) {
    return { color: 'bg-green-500', text: 'Connected' }
  } else {
    return { color: 'bg-red-500', text: 'Disconnected' }
  }
})

function togglePrivacy() {
  privacyMode.value = !privacyMode.value
}

async function checkConnection() {
  try {
    await api.getHealth()
    isConnected.value = true
  } catch (error) {
    isConnected.value = false
  }
}

async function loadAccountInfo() {
  try {
    accountInfo.value = await api.getAccountInfo()
  } catch (error) {
    console.error('Failed to load account info:', error)
  }
}

function connectWebSocket() {
  ws.value = api.initSocket()
  
  ws.value.on('account_update', (data) => {
    if (data && data.data) {
      accountInfo.value = data.data
    }
  })

  ws.value.on('connect_error', (error) => {
    console.error('WebSocket error:', error)
    isConnected.value = false
  })
}

onMounted(async () => {
  await checkConnection()
  if (isConnected.value) {
    await loadAccountInfo()
    connectWebSocket()
  }

  // Check connection every 30 seconds
  setInterval(checkConnection, 30000)
})

onUnmounted(() => {
  if (ws.value) {
    ws.value.close()
  }
})
</script>
