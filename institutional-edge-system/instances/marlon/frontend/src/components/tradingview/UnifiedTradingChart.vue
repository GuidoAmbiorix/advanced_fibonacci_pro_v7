
<template>
  <div class="unified-trading-chart">
    <!-- Mode Switcher -->
    <div class="mode-switcher">
      <button
        v-for="mode in modes"
        :key="mode.id"
        @click="switchMode(mode.id)"
        :class="['mode-btn', { active: currentMode === mode.id }]"
      >
        <component :is="mode.icon" class="w-5 h-5" />
        <span>{{ mode.label }}</span>
      </button>
      
      <!-- Timeframe Selector -->
      <div class="timeframe-selector">
        <select v-model="selectedTimeframe" @change="onTimeframeChange" class="tf-select">
          <option v-for="tf in timeframes" :key="tf" :value="tf">{{ tf }}</option>
        </select>
      </div>
    </div>

    <!-- Chart Container -->
    <div class="chart-wrapper">
      <div ref="chartContainer" class="chart-canvas"></div>

      <!-- Loading Overlay -->
      <div v-if="isLoading" class="loading-overlay">
        <div class="spinner"></div>
        <p class="text-gray-400 mt-2">{{ loadingMessage }}</p>
      </div>

      <!-- Chart Placeholder -->
      <div v-if="!chartInitialized && !isLoading" class="chart-placeholder">
        <ChartBarIcon class="w-16 h-16 text-gray-600 mb-2" />
        <p class="text-gray-400">Chart will render here</p>
      </div>
    </div>

    <!-- Playback Controls (Backtest Mode Only) -->
    <div v-if="currentMode === 'BACKTEST'" class="playback-controls">
      <button @click="runBacktestFromSlot" class="control-btn run-btn" :disabled="backtestRunning" title="Run Backtest">
        <RocketLaunchIcon class="w-5 h-5" />
      </button>
      
      <button @click="togglePlayback" class="control-btn" :disabled="!hasBacktestData" title="Play/Pause">
        <component :is="isPlaying ? PauseIcon : PlayIcon" class="w-5 h-5" />
      </button>

      <!-- Progress Bar -->
      <div class="progress-container">
        <input
          type="range"
          v-model="currentProgress"
          min="0"
          max="100"
          class="progress-slider"
          @input="seekTo"
          :disabled="!hasBacktestData"
        />
        <span class="progress-text">{{ currentProgress }}%</span>
      </div>

      <!-- Speed Control -->
      <select v-model="playbackSpeed" class="speed-select">
        <option :value="0.5">0.5x</option>
        <option :value="1">1x</option>
        <option :value="2">2x</option>
        <option :value="5">5x</option>
        <option :value="10">10x</option>
      </select>

      <button @click="restart" class="control-btn" title="Restart" :disabled="!hasBacktestData">
        <ArrowPathIcon class="w-5 h-5" />
      </button>
    </div>

    <!-- Bottom Panel (Context-Sensitive) -->
    <div class="bottom-panel">
      <!-- Live Analysis Panel -->
      <div v-if="currentMode === 'LIVE'" class="analysis-panel">
        <h4 class="panel-title">Market Analysis</h4>
        <div v-if="analysis" class="analysis-content">
          <div class="analysis-item">
            <span class="label">Trend:</span>
            <span :class="['value', getTrendClass(analysis.trend)]">{{ analysis.trend }}</span>
          </div>
          <div class="analysis-item">
            <span class="label">Confluence Score:</span>
            <span class="value">{{ analysis.confluence_score }}/10</span>
          </div>
          <div class="analysis-item">
            <span class="label">Patterns:</span>
            <span class="value">{{ analysis.patterns?.join(', ') || 'None' }}</span>
          </div>
        </div>
        <div v-else class="text-gray-400 text-sm">No analysis available</div>
      </div>

      <!-- Backtest Results Panel -->
      <div v-else-if="currentMode === 'BACKTEST'" class="results-panel">
        <h4 class="panel-title">Backtest Results</h4>
        <div class="results-grid">
          <div class="result-item">
            <span class="label">Balance:</span>
            <span class="value">${{ backtestMetrics.balance.toFixed(2) }}</span>
          </div>
          <div class="result-item">
            <span class="label">Trades:</span>
            <span class="value">{{ backtestMetrics.trades }}</span>
          </div>
          <div class="result-item">
            <span class="label">Win Rate:</span>
            <span class="value">{{ backtestMetrics.winRate.toFixed(1) }}%</span>
          </div>
          <div class="result-item">
            <span class="label">Profit Factor:</span>
            <span class="value">{{ backtestMetrics.profitFactor.toFixed(2) }}</span>
          </div>
        </div>
      </div>

      <!-- Comparison Panel -->
      <div v-else class="comparison-panel">
        <h4 class="panel-title">Strategy Comparison</h4>
        <p class="text-gray-400 text-sm">Select strategies to compare above</p>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch, computed } from 'vue'
import { createChart } from 'lightweight-charts'
import api from '@/services/api'
import {
  PlayIcon,
  PauseIcon,
  ArrowPathIcon,
  ChartBarIcon,
  RocketLaunchIcon,
  BeakerIcon,
  ArrowsRightLeftIcon
} from '@heroicons/vue/24/outline'
import { useChartData } from '../../composables/useChartData.js'

const props = defineProps({
  slotData: {
    type: Object,
    required: false
  },
  slotId: Number,
  mode: {
    type: String,
    default: 'LIVE'
  }
})

const modes = [
  { id: 'LIVE', label: 'Live', icon: RocketLaunchIcon },
  { id: 'BACKTEST', label: 'Backtest', icon: BeakerIcon },
  { id: 'COMPARE', label: 'Compare', icon: ArrowsRightLeftIcon }
]

// Available timeframes
const timeframes = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1']
const selectedTimeframe = ref(props.slotData?.timeframe || 'H1')

// Core state
const currentMode = ref(props.mode || 'LIVE')
const chartContainer = ref(null)
const chartInitialized = ref(false)
const isLoading = ref(false)
const loadingMessage = ref('Loading...')

let chart = null
let candleSeries = null
let markerSeries = null

// Data storage
const allHistoryData = ref([])
const visibleDataCount = ref(0)
const backtestTrades = ref([])

// Playback controls
const isPlaying = ref(false)
const currentProgress = ref(0)
const playbackSpeed = ref(1)
const backtestRunning = ref(false)
let playbackInterval = null

// Analysis data
const activeSlotId = computed(() => props.slotData?.id || props.slotId)
const chartDataComposable = activeSlotId.value ? useChartData(activeSlotId.value) : null
const analysis = chartDataComposable?.analysis || ref(null)
const latestPrice = chartDataComposable?.latestPrice || ref(0)

// Backtest metrics
const backtestMetrics = ref({
  balance: 100000,
  trades: 0,
  winRate: 0,
  profitFactor: 0
})

const hasBacktestData = computed(() => allHistoryData.value.length > 0 && currentMode.value === 'BACKTEST')

// Socket connection for backtest events
let socket = null

onMounted(async () => {
  console.log('UnifiedTradingChart Mounted. SlotData:', props.slotData)
  if (chartContainer.value) {
    initChart()
    await loadHistory()
    chartInitialized.value = true
  }
  
  // Setup socket for backtest events
  socket = api.getSocket()
  socket.on('backtest_progress', handleBacktestProgress)
  socket.on('backtest_trade', handleBacktestTrade)
  socket.on('backtest_complete', handleBacktestComplete)
})

onUnmounted(() => {
  if (playbackInterval) clearInterval(playbackInterval)
  if (socket) {
    socket.off('backtest_progress', handleBacktestProgress)
    socket.off('backtest_trade', handleBacktestTrade)
    socket.off('backtest_complete', handleBacktestComplete)
  }
  if (chart) {
    chart.remove()
    chart = null
  }
})

function initChart() {
  if (!chartContainer.value) return

  chart = createChart(chartContainer.value, {
    layout: {
      background: { type: 'solid', color: '#111827' },
      textColor: '#9CA3AF',
    },
    grid: {
      vertLines: { color: '#1F2937' },
      horzLines: { color: '#1F2937' },
    },
    width: chartContainer.value.clientWidth || 400,
    height: chartContainer.value.clientHeight || 300,
    timeScale: {
      timeVisible: true,
      secondsVisible: false,
    }
  })

  candleSeries = chart.addCandlestickSeries({
    upColor: '#22c55e',
    downColor: '#ef4444',
    borderVisible: false,
    wickUpColor: '#22c55e',
    wickDownColor: '#ef4444',
  })
  
  // Resize observer
  new ResizeObserver(entries => {
    if (entries.length === 0 || !chart) return
    const newRect = entries[0].contentRect
    chart.applyOptions({ width: newRect.width, height: newRect.height })
  }).observe(chartContainer.value)
}

async function loadHistory() {
  if (!props.slotData) {
    console.warn("No slotData provided")
    return
  }

  isLoading.value = true
  loadingMessage.value = 'Loading chart data...'

  try {
    const history = await api.getMarketHistory(props.slotData.symbol, selectedTimeframe.value)
    
    let rawData = Array.isArray(history) ? history : (history?.data || [])

    if (rawData.length > 0) {
      const data = rawData.map(d => ({
        time: new Date(d.time).getTime() / 1000,
        open: d.open,
        high: d.high,
        low: d.low,
        close: d.close
      }))
      data.sort((a, b) => a.time - b.time)
      
      allHistoryData.value = data
      visibleDataCount.value = data.length
      candleSeries.setData(data)
      chart.timeScale().fitContent()
    }
  } catch (e) {
    console.error("Failed to load history", e)
  } finally {
    isLoading.value = false
  }
}

function switchMode(newMode) {
  currentMode.value = newMode
  if (newMode === 'LIVE') {
    // Show all data in live mode
    if (allHistoryData.value.length > 0) {
      visibleDataCount.value = allHistoryData.value.length
      candleSeries.setData(allHistoryData.value)
      clearMarkers()
    }
  } else if (newMode === 'BACKTEST') {
    // Reset to beginning for backtest
    restart()
  }
}

async function onTimeframeChange() {
  console.log('Timeframe changed to:', selectedTimeframe.value)
  await loadHistory()
}

async function runBacktestFromSlot() {
  if (!props.slotData || backtestRunning.value) return
  
  backtestRunning.value = true
  isLoading.value = true
  loadingMessage.value = 'Starting backtest...'
  
  // Reset state
  backtestTrades.value = []
  backtestMetrics.value = { balance: 100000, trades: 0, winRate: 0, profitFactor: 0 }
  
  try {
    const config = {
      symbol: props.slotData.symbol,
      timeframe: props.slotData.timeframe,
      start_date: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(), // 30 days ago
      end_date: new Date().toISOString(),
      initial_balance: 100000,
      risk_percent: props.slotData.risk_percent || 1.0,
      strategy_mode: 'SWING',
      direction_filter: props.slotData.direction_filter || 'BOTH',
      enable_vwap_strategy: props.slotData.enable_vwap_strategy !== false,
      enable_stoch_strategy: props.slotData.enable_stoch_strategy !== false,
      enable_institutional_strategy: props.slotData.enable_institutional_strategy !== false,
      enable_fibonacci_strategy: props.slotData.enable_fibonacci_strategy !== false,
      min_confluence_score: props.slotData.min_confluence_score || 7,
      tp_ratio: props.slotData.tp_ratio || 2.0,
      sl_atr_multiplier: props.slotData.sl_atr_multiplier || 1.5,
      tsl_mode: props.slotData.tsl_mode || 'TIERED',
      enable_trailing_stop: true
    }
    
    const response = await api.runBacktest(config)
    console.log('Backtest started:', response)
    loadingMessage.value = `Backtest running (Session #${response.session_id})...`
  } catch (e) {
    console.error('Failed to start backtest:', e)
    backtestRunning.value = false
    isLoading.value = false
  }
}

function handleBacktestProgress(data) {
  loadingMessage.value = `Backtest: ${data.progress.toFixed(1)}%`
  currentProgress.value = Math.round(data.progress)
  
  if (data.stats) {
    backtestMetrics.value.balance = data.stats.balance || 100000
    backtestMetrics.value.trades = data.stats.trades || 0
  }
}

function handleBacktestTrade(data) {
  console.log('Backtest trade:', data.trade)
  backtestTrades.value.push(data.trade)
  updateTradeMarkers()
}

function handleBacktestComplete(data) {
  console.log('Backtest complete:', data)
  backtestRunning.value = false
  isLoading.value = false
  
  if (data.results) {
    backtestMetrics.value = {
      balance: 100000 + (data.results.net_profit || 0),
      trades: data.results.total_trades || 0,
      winRate: data.results.win_rate || 0,
      profitFactor: data.results.profit_factor || 0
    }
  }
  
  currentProgress.value = 100
}

function updateTradeMarkers() {
  if (!candleSeries || backtestTrades.value.length === 0) return
  
  const markers = backtestTrades.value.map(trade => {
    const entryMarker = {
      time: new Date(trade.entry_time).getTime() / 1000,
      position: trade.trade_type === 'BUY' ? 'belowBar' : 'aboveBar',
      color: trade.trade_type === 'BUY' ? '#22c55e' : '#ef4444',
      shape: trade.trade_type === 'BUY' ? 'arrowUp' : 'arrowDown',
      text: trade.trade_type === 'BUY' ? 'BUY' : 'SELL'
    }
    
    const markers = [entryMarker]
    
    if (trade.exit_time) {
      markers.push({
        time: new Date(trade.exit_time).getTime() / 1000,
        position: 'inBar',
        color: trade.pnl >= 0 ? '#22c55e' : '#ef4444',
        shape: 'circle',
        text: `${trade.pnl >= 0 ? '+' : ''}${trade.pnl?.toFixed(2) || '0'}`
      })
    }
    
    return markers
  }).flat()
  
  // Sort markers by time
  markers.sort((a, b) => a.time - b.time)
  candleSeries.setMarkers(markers)
}

function clearMarkers() {
  if (candleSeries) {
    candleSeries.setMarkers([])
  }
}

function togglePlayback() {
  if (!hasBacktestData.value) return
  
  isPlaying.value = !isPlaying.value
  
  if (isPlaying.value) {
    startPlayback()
  } else {
    stopPlayback()
  }
}

function startPlayback() {
  if (playbackInterval) clearInterval(playbackInterval)
  
  const totalBars = allHistoryData.value.length
  if (totalBars === 0) return
  
  // Start from current position
  if (visibleDataCount.value >= totalBars) {
    visibleDataCount.value = Math.max(1, Math.floor(totalBars * 0.1)) // Start at 10%
  }
  
  const baseInterval = 100 // ms per bar at 1x speed
  const interval = baseInterval / playbackSpeed.value
  
  playbackInterval = setInterval(() => {
    if (visibleDataCount.value < totalBars) {
      visibleDataCount.value++
      const visibleData = allHistoryData.value.slice(0, visibleDataCount.value)
      candleSeries.setData(visibleData)
      chart.timeScale().scrollToPosition(0, false)
      
      currentProgress.value = Math.round((visibleDataCount.value / totalBars) * 100)
    } else {
      stopPlayback()
      isPlaying.value = false
    }
  }, interval)
}

function stopPlayback() {
  if (playbackInterval) {
    clearInterval(playbackInterval)
    playbackInterval = null
  }
}

function seekTo() {
  if (!hasBacktestData.value) return
  
  stopPlayback()
  isPlaying.value = false
  
  const totalBars = allHistoryData.value.length
  const targetCount = Math.max(1, Math.floor((currentProgress.value / 100) * totalBars))
  visibleDataCount.value = targetCount
  
  const visibleData = allHistoryData.value.slice(0, targetCount)
  candleSeries.setData(visibleData)
  chart.timeScale().fitContent()
}

function restart() {
  stopPlayback()
  isPlaying.value = false
  currentProgress.value = 0
  visibleDataCount.value = Math.max(1, Math.floor(allHistoryData.value.length * 0.1))
  
  if (allHistoryData.value.length > 0) {
    candleSeries.setData(allHistoryData.value.slice(0, visibleDataCount.value))
    chart.timeScale().fitContent()
  }
  
  clearMarkers()
  backtestTrades.value = []
}

function getTrendClass(trend) {
  if (trend === 'BULLISH') return 'text-green-400'
  if (trend === 'BEARISH') return 'text-red-400'
  return 'text-gray-400'
}

// Watch playback speed changes
watch(playbackSpeed, () => {
  if (isPlaying.value) {
    stopPlayback()
    startPlayback()
  }
})
</script>

<style scoped>
.unified-trading-chart {
  @apply flex flex-col h-full bg-gray-800 rounded-lg border border-gray-700 overflow-hidden;
}

.mode-switcher {
  @apply flex-none flex border-b border-gray-700 bg-gray-900;
}

.mode-btn {
  @apply flex items-center gap-2 px-4 py-3 text-gray-400 hover:bg-gray-800 transition-colors;
}

.mode-btn.active {
  @apply bg-gray-800 text-blue-400 border-b-2 border-blue-400;
}

.timeframe-selector {
  @apply ml-auto flex items-center px-2;
}

.tf-select {
  @apply bg-gray-700 text-white px-3 py-2 rounded text-sm font-medium border border-gray-600 hover:border-gray-500 focus:outline-none focus:border-blue-500;
}

.chart-wrapper {
  @apply flex-1 relative w-full bg-gray-900 min-h-[350px];
}

.chart-canvas {
  @apply w-full h-full;
}

.chart-placeholder,
.loading-overlay {
  @apply absolute inset-0 flex flex-col items-center justify-center;
}

.loading-overlay {
  @apply bg-gray-900 bg-opacity-80;
}

.spinner {
  @apply w-8 h-8 border-4 border-blue-500 border-t-transparent rounded-full animate-spin;
}

.playback-controls {
  @apply flex items-center gap-2 p-2 bg-gray-900 border-t border-gray-700;
}

.control-btn {
  @apply p-2 bg-gray-700 hover:bg-gray-600 rounded text-gray-300 disabled:opacity-50 disabled:cursor-not-allowed;
}

.run-btn {
  @apply bg-blue-600 hover:bg-blue-700 text-white;
}

.progress-container {
  @apply flex-1 flex items-center gap-2;
}

.progress-slider {
  @apply flex-1;
}

.progress-text {
  @apply text-sm text-gray-400 min-w-[3rem] text-right;
}

.speed-select {
  @apply bg-gray-700 text-white px-2 py-1 rounded text-sm;
}

.bottom-panel {
  @apply p-3 bg-gray-900 border-t border-gray-700;
}

.panel-title {
  @apply text-sm font-semibold text-white mb-2;
}

.analysis-content, .results-grid {
  @apply space-y-1;
}

.results-grid {
  @apply grid grid-cols-4 gap-2;
}

.analysis-item, .result-item {
  @apply flex items-center gap-2 text-sm;
}

.label {
  @apply text-gray-400;
}

.value {
  @apply text-white font-semibold;
}
</style>
