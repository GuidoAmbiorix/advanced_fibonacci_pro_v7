<template>
  <div class="kelly-calculator bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-6 shadow-2xl">
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <div class="flex items-center gap-3">
        <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-emerald-500 to-cyan-500 flex items-center justify-center">
          <span class="text-xl">📊</span>
        </div>
        <div>
          <h3 class="text-lg font-bold text-white">Kelly Position Sizing</h3>
          <p class="text-xs text-gray-400">Optimal capital allocation</p>
        </div>
      </div>
      <button 
        @click="showHelp = !showHelp"
        class="w-8 h-8 rounded-lg bg-gray-700/50 hover:bg-gray-600/50 flex items-center justify-center text-gray-400 hover:text-white transition-colors"
      >
        ?
      </button>
    </div>

    <!-- Help Panel -->
    <transition name="slide">
      <div v-if="showHelp" class="mb-6 p-4 rounded-xl bg-cyan-500/10 border border-cyan-500/30 text-sm text-cyan-200">
        <p class="mb-2"><strong>Kelly Formula:</strong> f* = (bp - q) / b</p>
        <p class="text-xs text-cyan-300/70">
          Determines optimal fraction of capital to allocate per trade for maximum long-term growth.
          Half-Kelly is recommended for safety.
        </p>
      </div>
    </transition>

    <!-- Input Section -->
    <div class="grid grid-cols-3 gap-4 mb-6">
      <!-- Win Rate -->
      <div class="space-y-2">
        <label class="text-xs font-medium text-gray-400 uppercase tracking-wider">Win Rate</label>
        <div class="relative">
          <input
            v-model.number="winRate"
            type="number"
            min="0"
            max="100"
            step="0.1"
            class="w-full px-4 py-3 rounded-xl bg-gray-800/50 border border-gray-700/50 text-white text-center font-mono text-lg focus:ring-2 focus:ring-cyan-500/50 focus:border-cyan-500/50 transition-all"
            @input="calculate"
          />
          <span class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500">%</span>
        </div>
      </div>

      <!-- Risk/Reward -->
      <div class="space-y-2">
        <label class="text-xs font-medium text-gray-400 uppercase tracking-wider">Risk/Reward</label>
        <input
          v-model.number="riskReward"
          type="number"
          min="0.1"
          max="10"
          step="0.1"
          class="w-full px-4 py-3 rounded-xl bg-gray-800/50 border border-gray-700/50 text-white text-center font-mono text-lg focus:ring-2 focus:ring-cyan-500/50 focus:border-cyan-500/50 transition-all"
          @input="calculate"
        />
      </div>

      <!-- Mode Selector -->
      <div class="space-y-2">
        <label class="text-xs font-medium text-gray-400 uppercase tracking-wider">Mode</label>
        <div class="flex rounded-xl bg-gray-800/50 border border-gray-700/50 p-1">
          <button
            v-for="mode in ['Full', 'Half', '¼']"
            :key="mode"
            @click="selectedMode = mode; calculate()"
            class="flex-1 py-2 rounded-lg text-sm font-medium transition-all"
            :class="selectedMode === mode 
              ? 'bg-gradient-to-r from-cyan-500 to-emerald-500 text-white shadow-lg' 
              : 'text-gray-400 hover:text-white'"
          >
            {{ mode }}
          </button>
        </div>
      </div>
    </div>

    <!-- Account Balance -->
    <div class="mb-6">
      <label class="text-xs font-medium text-gray-400 uppercase tracking-wider">Account Balance</label>
      <div class="relative mt-2">
        <span class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-500">$</span>
        <input
          v-model.number="accountBalance"
          type="number"
          min="100"
          step="100"
          class="w-full pl-8 pr-4 py-3 rounded-xl bg-gray-800/50 border border-gray-700/50 text-white font-mono text-lg focus:ring-2 focus:ring-cyan-500/50 focus:border-cyan-500/50 transition-all"
          @input="calculate"
        />
      </div>
    </div>

    <!-- Divider -->
    <div class="h-px bg-gradient-to-r from-transparent via-gray-600 to-transparent mb-6"></div>

    <!-- Results Section -->
    <div class="space-y-4">
      <!-- Main Result: Optimal Leverage -->
      <div class="p-5 rounded-xl bg-gradient-to-r from-emerald-500/20 to-cyan-500/20 border border-emerald-500/30">
        <div class="text-xs font-medium text-emerald-400 uppercase tracking-wider mb-2">
          Recommended Leverage
        </div>
        <div class="flex items-baseline gap-2">
          <span class="text-4xl font-bold text-white">{{ displayLeverage }}</span>
          <span class="text-xl text-emerald-400">x</span>
        </div>
        <div class="text-sm text-gray-400 mt-1">
          {{ selectedMode }} Kelly
        </div>
      </div>

      <!-- Secondary Metrics -->
      <div class="grid grid-cols-2 gap-4">
        <!-- Position Size -->
        <div class="p-4 rounded-xl bg-gray-800/50 border border-gray-700/50">
          <div class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-1">
            Optimal Position
          </div>
          <div class="text-xl font-bold text-cyan-400">
            ${{ formatNumber(result?.optimal_position_dollars || 0) }}
          </div>
        </div>

        <!-- Max Risk -->
        <div class="p-4 rounded-xl bg-gray-800/50 border border-gray-700/50">
          <div class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-1">
            Max Risk/Trade
          </div>
          <div class="text-xl font-bold text-orange-400">
            ${{ formatNumber(result?.max_risk_dollars || 0) }}
          </div>
        </div>
      </div>

      <!-- Expected Growth -->
      <div class="p-4 rounded-xl bg-gray-800/50 border border-gray-700/50">
        <div class="flex items-center justify-between">
          <div>
            <div class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-1">
              Expected Growth Rate
            </div>
            <div class="text-xl font-bold text-purple-400">
              {{ (result?.expected_growth_rate || 0).toFixed(2) }}% <span class="text-sm text-gray-500">annually</span>
            </div>
          </div>
          <div class="text-right">
            <div class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-1">
              Sharpe Ratio
            </div>
            <div class="text-xl font-bold text-blue-400">
              {{ (result?.sharpe_ratio || 0).toFixed(2) }}
            </div>
          </div>
        </div>
      </div>

      <!-- All Kelly Values -->
      <div class="grid grid-cols-3 gap-3">
        <div 
          v-for="(value, label) in kellyValues"
          :key="label"
          class="p-3 rounded-lg text-center transition-all cursor-pointer"
          :class="getKellyClass(label)"
          @click="selectKellyMode(label)"
        >
          <div class="text-xs text-gray-400 mb-1">{{ label }}</div>
          <div class="text-lg font-bold font-mono">{{ value.toFixed(2) }}x</div>
        </div>
      </div>

      <!-- Warnings -->
      <div v-if="result?.warnings?.length" class="space-y-2">
        <div 
          v-for="(warning, idx) in result.warnings"
          :key="idx"
          class="p-3 rounded-lg bg-amber-500/20 border border-amber-500/30 text-sm text-amber-200 flex items-start gap-2"
        >
          <span>⚠️</span>
          <span>{{ warning }}</span>
        </div>
      </div>
    </div>

    <!-- Loading State -->
    <div v-if="loading" class="absolute inset-0 bg-slate-900/50 backdrop-blur-sm rounded-2xl flex items-center justify-center">
      <div class="animate-spin w-8 h-8 border-2 border-cyan-500 border-t-transparent rounded-full"></div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import api from '../services/api'

// Props
const props = defineProps({
  initialWinRate: { type: Number, default: 55 },
  initialRR: { type: Number, default: 2.0 },
  initialBalance: { type: Number, default: 10000 }
})

// State
const winRate = ref(props.initialWinRate)
const riskReward = ref(props.initialRR)
const accountBalance = ref(props.initialBalance)
const selectedMode = ref('Half')
const showHelp = ref(false)
const loading = ref(false)
const result = ref(null)

// Computed
const displayLeverage = computed(() => {
  if (!result.value) return '0.00'
  
  switch (selectedMode.value) {
    case 'Full':
      return result.value.optimal_leverage?.toFixed(2) || '0.00'
    case 'Half':
      return result.value.half_kelly?.toFixed(2) || '0.00'
    case '¼':
      return result.value.quarter_kelly?.toFixed(2) || '0.00'
    default:
      return result.value.half_kelly?.toFixed(2) || '0.00'
  }
})

const kellyValues = computed(() => ({
  'Full': result.value?.optimal_leverage || 0,
  'Half': result.value?.half_kelly || 0,
  'Quarter': result.value?.quarter_kelly || 0
}))

// Methods
const calculate = async () => {
  if (winRate.value <= 0 || riskReward.value <= 0 || accountBalance.value <= 0) {
    return
  }

  loading.value = true
  
  try {
    // Try API first
    const response = await api.post('/kelly/quick', null, {
      params: {
        win_rate: winRate.value,
        risk_reward: riskReward.value,
        account_balance: accountBalance.value
      }
    })
    result.value = response.data
  } catch (err) {
    // Fallback: calculate locally
    console.log('Using local Kelly calculation')
    result.value = calculateLocal()
  } finally {
    loading.value = false
  }
}

const calculateLocal = () => {
  const p = winRate.value / 100
  const q = 1 - p
  const b = riskReward.value
  
  // Kelly formula: f* = (bp - q) / b
  let optimalF = (b * p - q) / b
  optimalF = Math.max(0, optimalF)
  
  const halfKelly = optimalF / 2
  const quarterKelly = optimalF / 4
  
  // Approximate Sharpe
  const avgLoss = 100
  const avgWin = avgLoss * b
  const expectancy = p * avgWin - q * avgLoss
  
  return {
    optimal_leverage: optimalF,
    half_kelly: halfKelly,
    quarter_kelly: quarterKelly,
    recommended_leverage: halfKelly,
    expected_growth_rate: expectancy > 0 ? (2 + optimalF * 10) : 0,
    sharpe_ratio: expectancy / 100,
    win_rate: winRate.value,
    avg_win: avgWin,
    avg_loss: avgLoss,
    risk_reward_ratio: b,
    optimal_position_dollars: halfKelly * accountBalance.value,
    max_risk_dollars: Math.min(accountBalance.value * 0.02, halfKelly * accountBalance.value * 0.1),
    warnings: optimalF > 4 ? ['High leverage warning'] : []
  }
}

const formatNumber = (num) => {
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0
  }).format(num)
}

const getKellyClass = (label) => {
  const isActive = (label === 'Full' && selectedMode.value === 'Full') ||
                   (label === 'Half' && selectedMode.value === 'Half') ||
                   (label === 'Quarter' && selectedMode.value === '¼')
  
  return isActive 
    ? 'bg-cyan-500/30 border border-cyan-500/50' 
    : 'bg-gray-800/30 border border-gray-700/30 hover:bg-gray-700/50'
}

const selectKellyMode = (label) => {
  if (label === 'Full') selectedMode.value = 'Full'
  else if (label === 'Half') selectedMode.value = 'Half'
  else selectedMode.value = '¼'
}

// Lifecycle
onMounted(() => {
  calculate()
})

// Watch for external changes
watch([() => props.initialWinRate, () => props.initialRR, () => props.initialBalance], () => {
  winRate.value = props.initialWinRate
  riskReward.value = props.initialRR
  accountBalance.value = props.initialBalance
  calculate()
})
</script>

<style scoped>
.kelly-calculator {
  position: relative;
}

.slide-enter-active,
.slide-leave-active {
  transition: all 0.3s ease;
}

.slide-enter-from,
.slide-leave-to {
  opacity: 0;
  transform: translateY(-10px);
}

input[type="number"]::-webkit-inner-spin-button,
input[type="number"]::-webkit-outer-spin-button {
  -webkit-appearance: none;
  margin: 0;
}

input[type="number"] {
  -moz-appearance: textfield;
}
</style>
