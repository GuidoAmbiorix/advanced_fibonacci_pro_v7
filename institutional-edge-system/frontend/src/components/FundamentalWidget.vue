<template>
  <div class="glass-panel h-full flex flex-col">
    <div class="card-header">
      <h2 class="text-xl font-bold flex items-center gap-2">
        <span class="text-2xl">📊</span>
        <span class="bg-clip-text text-transparent bg-gradient-to-r from-blue-400 to-cyan-300">Fundamentals</span>
      </h2>
      <div v-if="loading" class="animate-spin rounded-full h-4 w-4 border-b-2 border-neon-blue"></div>
    </div>

    <div class="card-body">
      <div v-if="!symbol" class="text-center text-gray-400 py-8">
        Select a symbol to view fundamentals
      </div>

      <div v-else-if="error" class="text-center text-red-400 py-8">
        {{ error }}
      </div>

      <div v-else-if="data" class="space-y-6">
        <!-- Header -->
        <div class="flex justify-between items-start">
          <div v-if="data.overview">
            <h3 class="text-2xl font-bold">{{ data.overview.Symbol }}</h3>
            <p class="text-sm text-gray-400">{{ data.overview.Sector }} | {{ data.overview.Industry }}</p>
          </div>
          <div v-else>
            <h3 class="text-2xl font-bold">{{ symbol }}</h3>
            <p class="text-sm text-gray-400">Market Data</p>
          </div>

          <div class="text-right" v-if="data.sentiment">
            <div class="text-sm text-gray-400">Sentiment</div>
            <div 
              class="text-lg font-bold px-3 py-1 rounded inline-block mt-1"
              :class="getSentimentClass(data.sentiment.sentiment_label)"
            >
              {{ data.sentiment.sentiment_label }}
            </div>
          </div>
        </div>

        <!-- Key Metrics -->
        <div v-if="data.overview" class="grid grid-cols-2 gap-4">
          <div class="bg-gray-800/50 p-3 rounded">
            <div class="text-xs text-gray-400">PE Ratio</div>
            <div class="text-lg font-semibold">{{ data.overview.PE_Ratio || 'N/A' }}</div>
          </div>
          <div class="bg-gray-800/50 p-3 rounded">
            <div class="text-xs text-gray-400">EPS</div>
            <div class="text-lg font-semibold">{{ data.overview.EPS || 'N/A' }}</div>
          </div>
          <div class="bg-gray-800/50 p-3 rounded">
            <div class="text-xs text-gray-400">Div Yield</div>
            <div class="text-lg font-semibold">{{ data.overview.DividendYield ? (data.overview.DividendYield * 100).toFixed(2) + '%' : 'N/A' }}</div>
          </div>
          <div class="bg-gray-800/50 p-3 rounded">
            <div class="text-xs text-gray-400">52W High</div>
            <div class="text-lg font-semibold">{{ data.overview['52WeekHigh'] || 'N/A' }}</div>
          </div>
        </div>
        <div v-else class="text-center text-gray-500 py-4 bg-gray-800/30 rounded">
          <p>Fundamental data not available for this asset class.</p>
          <p class="text-xs mt-1">AlphaVantage provides full data mostly for US Stocks.</p>
        </div>

        <!-- Description -->
        <div v-if="data.overview" class="text-sm text-gray-400 line-clamp-4">
          {{ data.overview.Description }}
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue'
import api from '../services/api'

const props = defineProps({
  symbol: {
    type: String,
    default: null
  }
})

const data = ref(null)
const loading = ref(false)
const error = ref(null)

const fetchFundamentals = async () => {
  if (!props.symbol) return
  
  loading.value = true
  error.value = null
  data.value = null
  
  try {
    const response = await api.getFundamentals(props.symbol)
    data.value = response
  } catch (err) {
    console.error('Error fetching fundamentals:', err)
    error.value = 'Failed to load fundamental data'
  } finally {
    loading.value = false
  }
}

watch(() => props.symbol, () => {
  fetchFundamentals()
})

onMounted(() => {
  if (props.symbol) {
    fetchFundamentals()
  }
})

const getSentimentClass = (label) => {
  if (label.includes('Bullish')) return 'bg-green-900/50 text-green-400'
  if (label.includes('Bearish')) return 'bg-red-900/50 text-red-400'
  return 'bg-gray-700 text-gray-300'
}
</script>
