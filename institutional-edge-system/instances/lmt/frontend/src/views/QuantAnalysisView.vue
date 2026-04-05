<template>
  <div class="min-h-screen bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900 p-6">
    <!-- Header -->
    <div class="mb-8">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-4">
          <router-link to="/" class="text-gray-400 hover:text-white transition-colors">
            ← Back
          </router-link>
          <div>
            <h1 class="text-3xl font-bold text-white">
              Quantitative Analysis Center
            </h1>
            <p class="text-gray-400 text-sm mt-1">
              Advanced tools from Dr. Ernest Chan's "Quantitative Trading"
            </p>
          </div>
        </div>
        
        <!-- Symbol Selector -->
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2 bg-gray-800/50 rounded-xl px-4 py-2 border border-gray-700/50">
            <label class="text-xs text-gray-400 uppercase">Symbol</label>
            <select 
              v-model="selectedSymbol"
              class="bg-transparent text-white font-mono focus:outline-none"
              @change="onSymbolChange"
            >
              <option v-for="sym in symbols" :key="sym" :value="sym">{{ sym }}</option>
            </select>
          </div>
          
          <div class="flex items-center gap-2 bg-gray-800/50 rounded-xl px-4 py-2 border border-gray-700/50">
            <label class="text-xs text-gray-400 uppercase">Timeframe</label>
            <select 
              v-model="selectedTimeframe"
              class="bg-transparent text-white font-mono focus:outline-none"
              @change="onTimeframeChange"
            >
              <option v-for="tf in timeframes" :key="tf" :value="tf">{{ tf }}</option>
            </select>
          </div>
        </div>
      </div>
    </div>

    <!-- Tab Navigation -->
    <div class="flex gap-2 mb-6 bg-gray-800/30 rounded-xl p-1.5 w-fit">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        @click="activeTab = tab.id"
        class="px-5 py-2.5 rounded-lg font-medium text-sm transition-all flex items-center gap-2"
        :class="activeTab === tab.id 
          ? 'bg-gradient-to-r from-cyan-500 to-emerald-500 text-white shadow-lg' 
          : 'text-gray-400 hover:text-white hover:bg-gray-700/50'"
      >
        <span>{{ tab.icon }}</span>
        <span>{{ tab.label }}</span>
      </button>
    </div>

    <!-- Tab Content -->
    <div class="grid grid-cols-12 gap-6">
      <!-- Kelly Calculator Tab -->
      <template v-if="activeTab === 'kelly'">
        <div class="col-span-5">
          <KellyCalculator
            :initial-win-rate="strategyStats.winRate"
            :initial-r-r="strategyStats.riskReward"
            :initial-balance="accountBalance"
          />
        </div>
        
        <div class="col-span-7 space-y-6">
          <!-- Strategy Performance Card -->
          <div class="bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-6">
            <h3 class="text-lg font-bold text-white mb-4">Strategy Performance</h3>
            
            <div class="grid grid-cols-4 gap-4">
              <div class="p-4 rounded-xl bg-gray-800/50 border border-gray-700/50 text-center">
                <div class="text-2xl font-bold text-cyan-400">{{ strategyStats.totalTrades }}</div>
                <div class="text-xs text-gray-400">Total Trades</div>
              </div>
              <div class="p-4 rounded-xl bg-gray-800/50 border border-gray-700/50 text-center">
                <div class="text-2xl font-bold text-emerald-400">{{ strategyStats.winRate }}%</div>
                <div class="text-xs text-gray-400">Win Rate</div>
              </div>
              <div class="p-4 rounded-xl bg-gray-800/50 border border-gray-700/50 text-center">
                <div class="text-2xl font-bold text-purple-400">{{ strategyStats.riskReward }}</div>
                <div class="text-xs text-gray-400">Avg R:R</div>
              </div>
              <div class="p-4 rounded-xl bg-gray-800/50 border border-gray-700/50 text-center">
                <div class="text-2xl font-bold" :class="strategyStats.profitFactor >= 1.5 ? 'text-emerald-400' : 'text-orange-400'">
                  {{ strategyStats.profitFactor }}
                </div>
                <div class="text-xs text-gray-400">Profit Factor</div>
              </div>
            </div>
          </div>
          
          <!-- Kelly Comparison Chart Placeholder -->
          <div class="bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-6">
            <h3 class="text-lg font-bold text-white mb-4">Kelly Leverage Comparison</h3>
            <div class="h-64 flex items-center justify-center text-gray-500">
              <!-- Placeholder for ApexCharts -->
              <div class="text-center">
                <div class="text-6xl mb-3">R</div>
                <p>Equity curves with different Kelly fractions</p>
                <p class="text-sm text-gray-600">Full Kelly vs Half Kelly vs Quarter Kelly</p>
              </div>
            </div>
          </div>
        </div>
      </template>

      <!-- Regime Detection Tab -->
      <template v-else-if="activeTab === 'regime'">
        <div class="col-span-5">
          <RegimeIndicator
            :symbol="selectedSymbol"
            :timeframe="selectedTimeframe"
            :auto-refresh="true"
            @regime-change="onRegimeChange"
          />
        </div>
        
        <div class="col-span-7 space-y-6">
          <!-- Multi-Symbol Regimes -->
          <div class="bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-6">
            <h3 class="text-lg font-bold text-white mb-4">Portfolio Regime Overview</h3>
            
            <div class="grid grid-cols-3 gap-4">
              <div 
                v-for="(regime, symbol) in portfolioRegimes"
                :key="symbol"
                class="p-4 rounded-xl border transition-all cursor-pointer hover:scale-[1.02]"
                :class="getRegimeClass(regime)"
              >
                <div class="text-sm font-mono text-gray-400">{{ symbol }}</div>
                <div class="text-lg font-bold text-white flex items-center gap-2">
                  <span>{{ getRegimeIcon(regime) }}</span>
                  <span>{{ getRegimeShort(regime) }}</span>
                </div>
                <div class="text-xs text-gray-500 mt-1">
                  {{ regime.confidence || 0 }}% conf
                </div>
              </div>
            </div>
          </div>
          
          <!-- Regime History -->
          <div class="bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-6">
            <h3 class="text-lg font-bold text-white mb-4">Regime Transitions</h3>
            <div class="space-y-3">
              <div 
                v-for="(event, idx) in regimeHistory"
                :key="idx"
                class="flex items-center gap-4 p-3 rounded-lg bg-gray-800/30"
              >
                <div class="text-xs text-gray-500 font-mono w-24">{{ event.time }}</div>
                <div class="flex items-center gap-2">
                  <span class="px-2 py-1 rounded text-xs" :class="getRegimeBadgeClass(event.from)">
                    {{ event.from }}
                  </span>
                  <span class="text-gray-500">→</span>
                  <span class="px-2 py-1 rounded text-xs" :class="getRegimeBadgeClass(event.to)">
                    {{ event.to }}
                  </span>
                </div>
                <div class="text-sm text-gray-400">{{ event.symbol }}</div>
              </div>
              
              <div v-if="regimeHistory.length === 0" class="text-center text-gray-500 py-8">
                No regime transitions recorded yet
              </div>
            </div>
          </div>
        </div>
      </template>

      <!-- OOS Validation Tab (Placeholder) -->
      <template v-else-if="activeTab === 'oos'">
        <div class="col-span-12">
          <div class="bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-12 text-center">
            <div class="text-6xl mb-4">🔬</div>
            <h3 class="text-2xl font-bold text-white mb-2">Out-of-Sample Validation</h3>
            <p class="text-gray-400 mb-6">
              Coming soon: Test your strategy on unseen data to prevent overfitting
            </p>
            <div class="flex justify-center gap-4">
              <div class="px-6 py-3 rounded-xl bg-gray-800/50 border border-gray-700/50">
                <div class="text-sm text-gray-400">Train/Test Split</div>
                <div class="text-lg font-bold text-white">70% / 30%</div>
              </div>
              <div class="px-6 py-3 rounded-xl bg-gray-800/50 border border-gray-700/50">
                <div class="text-sm text-gray-400">Walk-Forward</div>
                <div class="text-lg font-bold text-white">Rolling Windows</div>
              </div>
              <div class="px-6 py-3 rounded-xl bg-gray-800/50 border border-gray-700/50">
                <div class="text-sm text-gray-400">Bias Detection</div>
                <div class="text-lg font-bold text-white">Data Snooping Score</div>
              </div>
            </div>
          </div>
        </div>
      </template>

      <!-- Cointegration Tab (Placeholder) -->
      <template v-else-if="activeTab === 'cointegration'">
        <div class="col-span-12">
          <div class="bg-gradient-to-br from-slate-900/90 via-slate-800/90 to-slate-900/90 rounded-2xl border border-white/10 p-12 text-center">
            <div class="text-6xl mb-4">🔗</div>
            <h3 class="text-2xl font-bold text-white mb-2">Cointegration Analysis</h3>
            <p class="text-gray-400 mb-6">
              Coming soon: Find cointegrated pairs for mean-reversion strategies
            </p>
            <div class="flex justify-center gap-4">
              <div class="px-6 py-3 rounded-xl bg-gray-800/50 border border-gray-700/50">
                <div class="text-sm text-gray-400">ADF Test</div>
                <div class="text-lg font-bold text-cyan-400">Stationarity</div>
              </div>
              <div class="px-6 py-3 rounded-xl bg-gray-800/50 border border-gray-700/50">
                <div class="text-sm text-gray-400">Hedge Ratio</div>
                <div class="text-lg font-bold text-purple-400">Optimal Weighting</div>
              </div>
              <div class="px-6 py-3 rounded-xl bg-gray-800/50 border border-gray-700/50">
                <div class="text-sm text-gray-400">Spread Z-Score</div>
                <div class="text-lg font-bold text-emerald-400">Entry Signals</div>
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue'
import KellyCalculator from '../components/KellyCalculator.vue'
import RegimeIndicator from '../components/RegimeIndicator.vue'
import api from '../services/api'

// State
const activeTab = ref('kelly')
const selectedSymbol = ref('EURUSD')
const selectedTimeframe = ref('H1')
const accountBalance = ref(10000)

const tabs = [
  { id: 'kelly', icon: 'R', label: 'Kelly Sizing' },
  { id: 'regime', icon: '🔥', label: 'Regime Detection' },
  { id: 'oos', icon: '🔬', label: 'OOS Validation' },
  { id: 'cointegration', icon: '🔗', label: 'Cointegration' }
]

const symbols = ['EURUSD', 'GBPUSD', 'USDJPY', 'XAUUSD', 'BTCUSD']
const timeframes = ['M5', 'M15', 'H1', 'H4', 'D1']

const strategyStats = reactive({
  totalTrades: 156,
  winRate: 62.5,
  riskReward: 2.1,
  profitFactor: 1.82
})

const portfolioRegimes = ref({
  'EURUSD': { regime: 'MEAN_REVERTING', confidence: 72 },
  'GBPUSD': { regime: 'TRENDING_BULL', confidence: 68 },
  'USDJPY': { regime: 'NEUTRAL', confidence: 45 },
  'XAUUSD': { regime: 'TRENDING_BULL', confidence: 81 },
  'BTCUSD': { regime: 'TRENDING_BEAR', confidence: 65 }
})

const regimeHistory = ref([])

// Methods
const onSymbolChange = () => {
  console.log('Symbol changed to:', selectedSymbol.value)
}

const onTimeframeChange = () => {
  console.log('Timeframe changed to:', selectedTimeframe.value)
}

const onRegimeChange = (event) => {
  regimeHistory.value.unshift({
    time: new Date().toLocaleTimeString(),
    from: event.previous,
    to: event.current,
    symbol: event.symbol
  })
  
  // Keep only last 10 events
  if (regimeHistory.value.length > 10) {
    regimeHistory.value = regimeHistory.value.slice(0, 10)
  }
}

const getRegimeIcon = (regime) => {
  const icons = {
    'TRENDING_BULL': '🔥',
    'TRENDING_BEAR': '📉',
    'MEAN_REVERTING': '↩️',
    'NEUTRAL': '⚖️'
  }
  return icons[regime?.regime] || '⏳'
}

const getRegimeShort = (regime) => {
  const labels = {
    'TRENDING_BULL': 'BULL',
    'TRENDING_BEAR': 'BEAR',
    'MEAN_REVERTING': 'MR',
    'NEUTRAL': 'FLAT'
  }
  return labels[regime?.regime] || '...'
}

const getRegimeClass = (regime) => {
  const classes = {
    'TRENDING_BULL': 'bg-emerald-500/10 border-emerald-500/30',
    'TRENDING_BEAR': 'bg-red-500/10 border-red-500/30',
    'MEAN_REVERTING': 'bg-cyan-500/10 border-cyan-500/30',
    'NEUTRAL': 'bg-gray-500/10 border-gray-500/30'
  }
  return classes[regime?.regime] || 'bg-gray-800/50 border-gray-700/50'
}

const getRegimeBadgeClass = (regime) => {
  const classes = {
    'TRENDING_BULL': 'bg-emerald-500/20 text-emerald-400',
    'TRENDING_BEAR': 'bg-red-500/20 text-red-400',
    'MEAN_REVERTING': 'bg-cyan-500/20 text-cyan-400',
    'NEUTRAL': 'bg-gray-500/20 text-gray-400'
  }
  return classes[regime] || 'bg-gray-500/20 text-gray-400'
}

// Load data
onMounted(async () => {
  try {
    // Try to fetch strategy stats from backend
    const response = await api.get('/stats/performance', { params: { days: 90 } })
    if (response.data) {
      strategyStats.totalTrades = response.data.total_trades || strategyStats.totalTrades
      strategyStats.winRate = response.data.win_rate || strategyStats.winRate
      strategyStats.profitFactor = response.data.profit_factor || strategyStats.profitFactor
    }
  } catch (err) {
    console.log('Using default strategy stats')
  }
  
  try {
    // Fetch account balance
    const accountResponse = await api.get('/mt5/account')
    if (accountResponse.data?.balance) {
      accountBalance.value = accountResponse.data.balance
    }
  } catch (err) {
    console.log('Using default account balance')
  }
})
</script>
