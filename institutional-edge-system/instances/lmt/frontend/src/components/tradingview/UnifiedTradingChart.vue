<template>
  <div class="unified-trading-chart">
    <!-- Mode Switcher -->
    <div class="mode-switcher">
      <button
        v-for="mode in modes"
        :key="mode.id"
        @click="currentMode = mode.id"
        :class="['mode-btn', { active: currentMode === mode.id }]"
      >
        <component :is="mode.icon" class="w-5 h-5" />
        <span>{{ mode.label }}</span>
      </button>
    </div>

    <!-- Chart Container -->
    <div class="chart-wrapper">
      <div ref="chartContainer" class="chart-canvas"></div>

      <!-- Chart Placeholder (until TradingView Lightweight Charts is integrated) -->
      <div v-if="!chartInitialized" class="chart-placeholder">
        <ChartBarIcon class="w-16 h-16 text-gray-600 mb-2" />
        <p class="text-gray-400">Chart will render here</p>
        <p class="text-sm text-gray-500">Requires TradingView Lightweight Charts library</p>
      </div>
    </div>

    <!-- Playback Controls (Backtest Mode Only) -->
    <div v-if="currentMode === 'BACKTEST'" class="playback-controls">
      <button @click="togglePlayback" class="control-btn">
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
        />
        <span class="progress-text">{{ currentProgress }}%</span>
      </div>

      <!-- Speed Control -->
      <select v-model="playbackSpeed" class="speed-select">
        <option :value="0.5">0.5x</option>
        <option :value="1">1x</option>
        <option :value="2">2x</option>
        <option :value="5">5x</option>
      </select>

      <button @click="restart" class="control-btn" title="Restart">
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
            <span class="value">{{ analysis.patterns.join(', ') || 'None' }}</span>
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

<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import {
  PlayIcon,
  PauseIcon,
  ArrowPathIcon,
  ChartBarIcon,
  RocketLaunchIcon,
  BeakerIcon,
  ArrowsRightLeftIcon
} from '@heroicons/vue/24/outline'
import { useChartData } from '../../composables/useChartData'

const props = defineProps<{
  slotId?: number
  backtestSessionId?: number
  mode?: 'LIVE' | 'BACKTEST' | 'COMPARE'
}>()

const modes = [
  { id: 'LIVE', label: 'Live', icon: RocketLaunchIcon },
  { id: 'BACKTEST', label: 'Backtest', icon: BeakerIcon },
  { id: 'COMPARE', label: 'Compare', icon: ArrowsRightLeftIcon }
]

const currentMode = ref(props.mode || 'LIVE')
const chartContainer = ref<HTMLElement>()
const chartInitialized = ref(false)

// Playback controls
const isPlaying = ref(false)
const currentProgress = ref(0)
const playbackSpeed = ref(1)

// Analysis data
const { analysis, latestPrice } = props.slotId ? useChartData(props.slotId) : { analysis: ref(null), latestPrice: ref(0) }

// Backtest metrics
const backtestMetrics = ref({
  balance: 100000,
  trades: 0,
  winRate: 0,
  profitFactor: 0
})

onMounted(() => {
  // TODO: Initialize TradingView Lightweight Charts
  // This is a placeholder - actual chart initialization would go here
  console.log('Chart container ready:', chartContainer.value)

  // For now, show placeholder
  chartInitialized.value = false
})

function togglePlayback() {
  isPlaying.value = !isPlaying.value
  // TODO: Implement actual playback logic
}

function seekTo() {
  // TODO: Implement seek functionality
  console.log('Seeking to:', currentProgress.value)
}

function restart() {
  currentProgress.value = 0
  isPlaying.value = false
  // TODO: Implement restart logic
}

function getTrendClass(trend: string): string {
  if (trend === 'BULLISH') return 'text-green-400'
  if (trend === 'BEARISH') return 'text-red-400'
  return 'text-gray-400'
}
</script>

<style scoped>
.unified-trading-chart {
  @apply bg-gray-800 rounded-lg border border-gray-700 overflow-hidden;
}

.mode-switcher {
  @apply flex border-b border-gray-700 bg-gray-900;
}

.mode-btn {
  @apply flex items-center gap-2 px-4 py-3 text-gray-400 hover:bg-gray-800 transition-colors;
}

.mode-btn.active {
  @apply bg-gray-800 text-blue-400 border-b-2 border-blue-400;
}

.chart-wrapper {
  @apply relative w-full h-96 bg-gray-900;
}

.chart-canvas {
  @apply w-full h-full;
}

.chart-placeholder {
  @apply absolute inset-0 flex flex-col items-center justify-center;
}

.playback-controls {
  @apply flex items-center gap-2 p-2 bg-gray-900 border-t border-gray-700;
}

.control-btn {
  @apply p-2 bg-gray-700 hover:bg-gray-600 rounded text-gray-300;
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
  @apply p-4 bg-gray-900 border-t border-gray-700;
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
