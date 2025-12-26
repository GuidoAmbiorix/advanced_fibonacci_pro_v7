/**
 * TradingView Integration - Composable for Chart Data Management
 * Handles WebSocket connections and real-time market data
 */

import { ref, onMounted, onUnmounted } from 'vue'
import { io } from 'socket.io-client'

export function useChartData(slotId) {
  const annotations = ref([])
  const analysis = ref(null)
  const latestPrice = ref(0)
  const isConnected = ref(false)

  let socket = null

  onMounted(() => {
    // Connect to Socket.IO server
    const backendUrl = import.meta.env.VITE_API_URL || 'http://localhost:8000'
    socket = io(backendUrl, {
      transports: ['websocket'],
      reconnection: true,
      reconnectionDelay: 1000,
      reconnectionAttempts: 5
    })

    socket.on('connect', () => {
      console.log('📡 WebSocket connected')
      isConnected.value = true

      // Subscribe to slot-specific updates
      socket?.emit('subscribe_slot', { slot_id: slotId })
    })

    socket.on('disconnect', () => {
      console.log('❌ WebSocket disconnected')
      isConnected.value = false
    })

    // Listen for market analysis updates
    socket.on('market_analysis', (data) => {
      if (data.slot_id === slotId) {
        annotations.value = data.annotations || []
        analysis.value = data.analysis || null
      }
    })

    // Listen for price updates
    socket.on('price_update', (data) => {
      if (data.slot_id === slotId) {
        latestPrice.value = data.price
      }
    })

    // Listen for new candles
    socket.on('new_candle', (data) => {
      if (data.slot_id === slotId) {
        // Emit event for chart to consume
        console.log('📊 New candle received:', data.candle)
      }
    })
  })

  onUnmounted(() => {
    if (socket) {
      socket.emit('unsubscribe_slot', { slot_id: slotId })
      socket.disconnect()
    }
  })

  return {
    annotations,
    analysis,
    latestPrice,
    isConnected
  }
}
