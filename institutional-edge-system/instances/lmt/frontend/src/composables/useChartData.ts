/**
 * TradingView Integration - Composable for Chart Data Management
 * Handles WebSocket connections and real-time market data
 */

import { ref, onMounted, onUnmounted } from 'vue'
import { io, Socket } from 'socket.io-client'

export interface Annotation {
  id: string
  type: 'order_block' | 'fvg' | 'liquidity_sweep' | 'user_zone'
  price: number
  time: number
  label?: string
  color?: string
}

export interface Analysis {
  trend: 'BULLISH' | 'BEARISH' | 'NEUTRAL'
  confluence_score: number
  patterns: string[]
  risk_level: 'LOW' | 'MEDIUM' | 'HIGH'
}

export function useChartData(slotId: number) {
  const annotations = ref<Annotation[]>([])
  const analysis = ref<Analysis | null>(null)
  const latestPrice = ref<number>(0)
  const isConnected = ref(false)

  let socket: Socket | null = null

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
    socket.on('market_analysis', (data: any) => {
      if (data.slot_id === slotId) {
        annotations.value = data.annotations || []
        analysis.value = data.analysis || null
      }
    })

    // Listen for price updates
    socket.on('price_update', (data: any) => {
      if (data.slot_id === slotId) {
        latestPrice.value = data.price
      }
    })

    // Listen for new candles
    socket.on('new_candle', (data: any) => {
      if (data.slot_id === slotId) {
        // Emit event for chart to consume
        console.log('R New candle received:', data.candle)
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
