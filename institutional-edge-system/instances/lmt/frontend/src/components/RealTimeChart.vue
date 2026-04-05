<template>
  <div class="w-full h-full relative">
    <Line v-if="chartData.datasets.length > 0" :data="chartData" :options="chartOptions" />
    <div v-else class="flex items-center justify-center h-full text-slate-500">
      <span v-if="error" class="text-red-400 flex flex-col items-center">
        <div class="flex items-center mb-2">
          <span class="mr-2">R</span> {{ error }}
        </div>
        <button @click="updateChart" class="px-3 py-1 bg-slate-700 hover:bg-slate-600 rounded text-xs text-white transition-colors">
          🔄 Retry
        </button>
      </span>
      <span v-else class="animate-pulse">Loading Market Data...</span>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { Line } from 'vue-chartjs'
import { Chart as ChartJS, CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler } from 'chart.js'
import api from '../services/api'

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler)

const props = defineProps({
  symbol: { type: String, default: 'BTCUSD' },
  timeframe: { type: String, default: 'H1' }
})

const error = ref(null)
const chartData = ref({ labels: [], datasets: [] })

const chartOptions = ref({
  responsive: true,
  maintainAspectRatio: false,
  scales: {
    y: {
      grid: { color: '#334155' },
      ticks: { color: '#94a3b8' }
    },
    x: {
      grid: { display: false },
      ticks: { display: false }
    }
  },
  plugins: {
    legend: { display: false },
    tooltip: {
      mode: 'index',
      intersect: false,
      backgroundColor: '#1e293b',
      titleColor: '#f8fafc',
      bodyColor: '#f8fafc',
      borderColor: '#334155',
      borderWidth: 1
    }
  },
  elements: {
    point: { radius: 0, hoverRadius: 4 },
    line: { tension: 0.1 }
  }
})

let interval = null

async function updateChart() {
  try {
    const history = await api.getMarketHistory(props.symbol, props.timeframe, 100)
    if (history && history.data) {
      error.value = null
      const prices = history.data.map(d => d.close)
      const labels = history.data.map(d => new Date(d.time).toLocaleTimeString())
      
      chartData.value = {
        labels: labels,
        datasets: [{
          label: props.symbol,
          data: prices,
          borderColor: '#10b981',
          backgroundColor: 'rgba(16, 185, 129, 0.1)',
          fill: true,
          borderWidth: 2
        }]
      }
    }
  } catch (e) {
    console.error("Chart update failed", e)
    error.value = "Connection Lost"
  }
}

onMounted(() => {
  updateChart()
  interval = setInterval(updateChart, 5000)
})

onUnmounted(() => {
  if (interval) clearInterval(interval)
})
</script>
