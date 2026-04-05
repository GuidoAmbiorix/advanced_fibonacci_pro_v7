<template>
  <div class="card h-full flex flex-col">
    <div class="card-header">
      <h3 class="text-sm font-bold text-primary uppercase tracking-wider flex items-center space-x-2">
        <span>R</span>
        <span>Fundamental Data</span>
      </h3>
      <div v-if="loading" class="animate-spin rounded-full h-4 w-4 border-b-2 border-accent"></div>
    </div>

    <div class="card-body flex-1 overflow-y-auto custom-scrollbar">
      <div v-if="!symbol" class="text-center text-slate-500 py-8 flex flex-col items-center justify-center h-full">
        <p>Select a symbol to view fundamentals</p>
      </div>

      <div v-else-if="error" class="text-center text-danger py-8">
        {{ error }}
      </div>

      <div v-else-if="data" class="space-y-6">
        <!-- Header -->
        <div class="flex justify-between items-start">
          <div v-if="data.overview">
            <h3 class="text-2xl font-bold text-primary">{{ data.overview.Symbol }}</h3>
            <p class="text-sm text-slate-500">{{ data.overview.Sector }} | {{ data.overview.Industry }}</p>
          </div>
          <div v-else>
            <h3 class="text-2xl font-bold text-primary">{{ symbol }}</h3>
            <p class="text-sm text-slate-500">Market Data</p>
          </div>

          <div class="text-right" v-if="data.sentiment">
            <div class="text-sm text-slate-500">Sentiment</div>
            <div 
              class="text-sm font-bold px-3 py-1 rounded inline-block mt-1"
              :class="getSentimentClass(data.sentiment.sentiment_label)"
            >
              {{ data.sentiment.sentiment_label }}
            </div>
          </div>
        </div>

        <!-- Key Metrics -->
        <div v-if="data.overview" class="grid grid-cols-2 gap-4">
          <div class="bg-slate-50 p-3 rounded border border-slate-200">
            <div class="text-xs text-slate-500">PE Ratio</div>
            <div class="text-lg font-semibold text-primary">{{ data.overview.PE_Ratio || 'N/A' }}</div>
          </div>
          <div class="bg-slate-50 p-3 rounded border border-slate-200">
            <div class="text-xs text-slate-500">EPS</div>
            <div class="text-lg font-semibold text-primary">{{ data.overview.EPS || 'N/A' }}</div>
          </div>
          <div class="bg-slate-50 p-3 rounded border border-slate-200">
            <div class="text-xs text-slate-500">Div Yield</div>
            <div class="text-lg font-semibold text-primary">{{ data.overview.DividendYield ? (data.overview.DividendYield * 100).toFixed(2) + '%' : 'N/A' }}</div>
          </div>
          <div class="bg-slate-50 p-3 rounded border border-slate-200">
            <div class="text-xs text-slate-500">52W High</div>
            <div class="text-lg font-semibold text-primary">{{ data.overview['52WeekHigh'] || 'N/A' }}</div>
          </div>
        </div>
        <div v-else class="text-center text-slate-500 py-4 bg-slate-50 rounded border border-slate-200">
          <p>Fundamental data not available for this asset class.</p>
          <p class="text-xs mt-1">AlphaVantage provides full data mostly for US Stocks.</p>
        </div>

        <!-- Description -->
        <div v-if="data.overview" class="text-sm text-slate-500 line-clamp-4">
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
