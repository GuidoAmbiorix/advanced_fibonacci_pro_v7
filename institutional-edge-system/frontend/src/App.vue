<template>
  <div class="min-h-screen bg-gray-900">
    <!-- Header -->
    <header class="bg-gray-800 border-b border-gray-700">
      <div class="max-w-7xl mx-auto px-4 py-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-4">
            <h1 class="text-2xl font-bold text-white">
              🎯 Institutional Edge <span class="text-blue-500">PRO</span>
            </h1>
            <span class="badge badge-info">v1.0</span>
          </div>

          <div class="flex items-center space-x-4">
            <!-- Connection Status -->
            <div class="flex items-center space-x-2">
              <div :class="connectionStatus.color" class="w-3 h-3 rounded-full"></div>
              <span class="text-sm text-gray-400">{{ connectionStatus.text }}</span>
            </div>

            <!-- Account Balance -->
            <div v-if="accountInfo" class="text-sm">
              <span class="text-gray-400">Balance:</span>
              <span class="text-white font-semibold ml-2">
                ${{ accountInfo.balance?.toFixed(2) || '0.00' }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main class="max-w-7xl mx-auto px-4 py-6">
      <Dashboard />
    </main>

    <!-- Footer -->
    <footer class="bg-gray-800 border-t border-gray-700 mt-12">
      <div class="max-w-7xl mx-auto px-4 py-4 text-center text-gray-400 text-sm">
        <p>© 2024 Institutional Edge PRO. Professional Trading System.</p>
      </div>
    </footer>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import Dashboard from './components/Dashboard.vue'
import api from './services/api'

const accountInfo = ref(null)
const isConnected = ref(false)
const ws = ref(null)

const connectionStatus = computed(() => {
  if (isConnected.value) {
    return { color: 'bg-green-500', text: 'Connected' }
  } else {
    return { color: 'bg-red-500', text: 'Disconnected' }
  }
})

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
  ws.value = api.createWebSocket(
    (data) => {
      if (data.type === 'account_update' && data.data) {
        accountInfo.value = data.data
      }
    },
    (error) => {
      console.error('WebSocket error:', error)
      isConnected.value = false
    }
  )
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
