<template>
  <div class="bg-gray-800 rounded-xl border border-gray-700 p-4">
    <div class="flex justify-between items-center mb-4">
      <h3 class="text-sm font-semibold text-gray-300">📊 Correlation Matrix</h3>
      <button 
        @click="fetchCorrelation"
        :disabled="loading"
        class="text-xs px-2 py-1 bg-gray-700 hover:bg-gray-600 rounded text-gray-400 transition-colors"
      >
        {{ loading ? '...' : '🔄' }}
      </button>
    </div>
    
    <!-- Diversification Score -->
    <div v-if="diversificationScore !== null" class="mb-4">
      <div class="flex justify-between items-center text-xs">
        <span class="text-gray-500">Diversification Score</span>
        <span :class="scoreColor" class="font-bold">{{ (diversificationScore * 100).toFixed(0) }}%</span>
      </div>
      <div class="w-full bg-gray-700 rounded-full h-2 mt-1">
        <div 
          class="h-2 rounded-full transition-all duration-500"
          :class="scoreBarColor"
          :style="{ width: (diversificationScore * 100) + '%' }"
        ></div>
      </div>
    </div>
    
    <!-- Heatmap Grid -->
    <div v-if="matrix && Object.keys(matrix).length > 0" class="overflow-x-auto">
      <table class="w-full text-xs">
        <thead>
          <tr>
            <th class="p-1"></th>
            <th v-for="sym in symbols" :key="'h-'+sym" class="p-1 text-gray-500 font-normal">
              {{ getShortSymbol(sym) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="sym1 in symbols" :key="'r-'+sym1">
            <td class="p-1 text-gray-500">{{ getShortSymbol(sym1) }}</td>
            <td 
              v-for="sym2 in symbols" 
              :key="'c-'+sym1+sym2"
              class="p-1 text-center font-mono"
              :class="getCellClass(sym1, sym2)"
            >
              {{ getCellValue(sym1, sym2) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    
    <!-- No Data -->
    <div v-else-if="!loading" class="text-center text-gray-600 py-4 text-xs">
      Click 🔄 to calculate correlations
    </div>
    
    <!-- Loading -->
    <div v-if="loading" class="text-center text-gray-500 py-4 text-xs">
      Calculating correlations...
    </div>
    
    <!-- Warnings -->
    <div v-if="warnings.length > 0" class="mt-3 space-y-1">
      <div 
        v-for="(warning, i) in warnings" 
        :key="i"
        class="text-xs px-2 py-1 rounded"
        :class="warning.includes('negatively') ? 'bg-green-900/30 text-green-400' : 'bg-yellow-900/30 text-yellow-400'"
      >
        {{ warning }}
      </div>
    </div>
    
    <!-- Legend -->
    <div class="mt-3 flex justify-center space-x-4 text-xs text-gray-500">
      <span><span class="inline-block w-3 h-3 bg-green-600 rounded mr-1"></span>Low</span>
      <span><span class="inline-block w-3 h-3 bg-yellow-600 rounded mr-1"></span>Mod</span>
      <span><span class="inline-block w-3 h-3 bg-red-600 rounded mr-1"></span>High</span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import axios from 'axios'

const props = defineProps({
  symbols: {
    type: Array,
    default: () => []
  }
})

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000'

const loading = ref(false)
const matrix = ref({})
const warnings = ref([])
const diversificationScore = ref(null)

const symbols = computed(() => props.symbols.filter(s => s))

// Watch for symbol changes
watch(() => props.symbols, () => {
  if (props.symbols.length >= 2) {
    fetchCorrelation()
  }
}, { deep: true })

const fetchCorrelation = async () => {
  if (symbols.value.length < 2) return
  
  loading.value = true
  try {
    const symbolsStr = symbols.value.join(',')
    const response = await axios.get(`${API_URL}/api/portfolio/correlation?symbols=${symbolsStr}`)
    
    matrix.value = response.data.matrix || {}
    warnings.value = response.data.warnings || []
    diversificationScore.value = response.data.diversification_score
  } catch (error) {
    console.error('Failed to fetch correlation:', error)
  } finally {
    loading.value = false
  }
}

const getShortSymbol = (sym) => {
  // Remove prefix like '#' and suffix, show last 6 chars
  return sym.replace('#', '').substring(0, 6)
}

const getCellValue = (sym1, sym2) => {
  if (sym1 === sym2) return '1.00'
  if (matrix.value[sym1] && matrix.value[sym1][sym2] !== undefined) {
    return matrix.value[sym1][sym2].toFixed(2)
  }
  return '-'
}

const getCellClass = (sym1, sym2) => {
  if (sym1 === sym2) return 'bg-gray-700 text-gray-400'
  
  const corr = matrix.value[sym1]?.[sym2] || 0
  const absCorr = Math.abs(corr)
  
  if (absCorr < 0.3) return 'bg-green-900/50 text-green-400'
  if (absCorr < 0.7) return 'bg-yellow-900/50 text-yellow-400'
  return 'bg-red-900/50 text-red-400'
}

const scoreColor = computed(() => {
  if (diversificationScore.value >= 0.7) return 'text-green-400'
  if (diversificationScore.value >= 0.4) return 'text-yellow-400'
  return 'text-red-400'
})

const scoreBarColor = computed(() => {
  if (diversificationScore.value >= 0.7) return 'bg-green-500'
  if (diversificationScore.value >= 0.4) return 'bg-yellow-500'
  return 'bg-red-500'
})
</script>
