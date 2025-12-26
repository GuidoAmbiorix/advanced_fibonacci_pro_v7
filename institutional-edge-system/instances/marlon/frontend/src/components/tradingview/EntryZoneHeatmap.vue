
<template>
  <div class="heatmap-container">
    <div class="heatmap-header">
      <h3 class="text-lg font-bold text-white">Entry Zone Heatmap</h3>
      <div class="heatmap-controls">
        <label class="text-sm text-gray-400">
          Bin Size:
          <select v-model="binSize" @change="loadHeatmap" class="ml-2 bg-gray-700 rounded px-2 py-1 text-white">
            <option :value="10">10 pips</option>
            <option :value="20">20 pips</option>
            <option :value="50">50 pips</option>
          </select>
        </label>
        <button @click="loadHeatmap" class="refresh-btn">
          <ArrowPathIcon class="w-4 h-4" />
        </button>
      </div>
    </div>

    <!-- Loading State -->
    <div v-if="loading" class="loading-state">
      <div class="spinner"></div>
      <p class="text-gray-400">Generating heatmap...</p>
    </div>

    <!-- Heatmap Visualization -->
    <div v-else-if="heatmapData" class="heatmap-content">
      <!-- Heatmap Bars -->
      <div class="heatmap-bars">
        <div
          v-for="bin in heatmapData.bins"
          :key="`${bin.price_low}-${bin.price_high}`"
          class="heatmap-bar"
          :style="getBarStyle(bin)"
          :title="`${bin.price_range}: ${bin.entry_count} entries, ${bin.win_rate.toFixed(1)}% WR`"
        >
          <span class="bar-label">{{ bin.price_range }}</span>
          <span class="bar-count">{{ bin.entry_count }}</span>
        </div>
      </div>

      <!-- Legend -->
      <div class="heatmap-legend">
        <span class="legend-label text-gray-400">Entry Frequency:</span>
        <div class="legend-gradient">
          <span class="legend-text text-gray-400">Low</span>
          <div class="gradient-bar"></div>
          <span class="legend-text text-gray-400">High</span>
        </div>
      </div>

      <!-- Statistics -->
      <div class="heatmap-stats">
        <div class="stat">
          <span class="stat-label">Most Active Zone:</span>
          <span class="stat-value">{{ heatmapData.most_active_zone.price_range }} ({{ heatmapData.most_active_zone.entry_count }} entries)</span>
        </div>
        <div class="stat">
          <span class="stat-label">Highest Win Rate Zone:</span>
          <span class="stat-value">{{ heatmapData.best_win_rate_zone.price_range }} ({{ heatmapData.best_win_rate_zone.win_rate.toFixed(1) }}% WR)</span>
        </div>
      </div>
    </div>

    <!-- Empty State -->
    <div v-else class="empty-state">
      <ChartBarIcon class="w-12 h-12 text-gray-600 mx-auto mb-2" />
      <p class="text-gray-400">No heatmap data available</p>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { ArrowPathIcon, ChartBarIcon } from '@heroicons/vue/24/outline'
import api from '@/services/api'

const props = defineProps({
  sessionId: Number
})

const binSize = ref(20)
const loading = ref(false)
const heatmapData = ref(null)

onMounted(() => {
  loadHeatmap()
})

async function loadHeatmap() {
  loading.value = true
  try {
    const data = await api.getHeatmap(props.sessionId, binSize.value)
    heatmapData.value = data
  } catch (error) {
    console.error('Failed to load heatmap:', error)
  } finally {
    loading.value = false
  }
}

function getBarStyle(bin) {
  const maxEntries = Math.max(...heatmapData.value.bins.map((b) => b.entry_count))
  const intensity = bin.entry_count / maxEntries
  const opacity = 0.2 + (intensity * 0.6) // Range from 0.2 to 0.8

  // Color based on win rate
  const color = bin.win_rate >= 50 ? '16, 185, 129' : '239, 68, 68' // Green or Red

  return {
    backgroundColor: `rgba(${color}, ${opacity})`,
    width: `${intensity * 100}%`,
    minWidth: '30px'
  }
}
</script>

<style scoped>
.heatmap-container {
  @apply bg-gray-800 rounded-lg border border-gray-700 p-4;
}

.heatmap-header {
  @apply flex items-center justify-between mb-4;
}

.heatmap-controls {
  @apply flex items-center gap-2;
}

.refresh-btn {
  @apply p-2 bg-gray-700 hover:bg-gray-600 rounded text-gray-300;
}

.loading-state {
  @apply flex flex-col items-center justify-center py-12;
}

.spinner {
  @apply w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mb-2;
}

.heatmap-content {
  @apply space-y-4;
}

.heatmap-bars {
  @apply space-y-1 max-h-96 overflow-y-auto;
}

.heatmap-bar {
  @apply relative flex items-center justify-between px-2 py-1 rounded transition-all hover:opacity-100;
}

.bar-label {
  @apply text-xs text-white font-mono;
}

.bar-count {
  @apply text-xs text-white font-bold;
}

.heatmap-legend {
  @apply flex items-center gap-4 pt-4 border-t border-gray-700;
}

.legend-gradient {
  @apply flex items-center gap-2;
}

.gradient-bar {
  @apply w-32 h-4 rounded;
  background: linear-gradient(to right, rgba(16, 185, 129, 0.2), rgba(16, 185, 129, 0.8));
}

.legend-text {
  @apply text-xs;
}

.heatmap-stats {
  @apply grid grid-cols-2 gap-4 p-4 bg-gray-900 rounded-lg;
}

.stat {
  @apply flex flex-col gap-1;
}

.stat-label {
  @apply text-xs text-gray-400;
}

.stat-value {
  @apply text-sm font-semibold text-white;
}

.empty-state {
  @apply text-center py-12;
}
</style>
