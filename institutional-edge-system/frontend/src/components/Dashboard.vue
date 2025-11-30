            </button>

            <button
              @click="toggleAutoRefresh"
              :class="autoRefresh ? 'btn-success' : 'btn-secondary'"
            >
              {{ autoRefresh ? '⏸️ Stop Auto' : '▶️ Auto Refresh' }}
            </button>
          </div>
        </div>

        <div v-if="lastUpdate" class="mt-4 text-sm text-gray-400">
          Last updated: {{ new Date(lastUpdate).toLocaleString() }}
        </div>
      </div>
    </div>

    <!-- Trading Signals -->
    <SignalsPanel :signals="signals" @execute="executeSignal" />

    <!-- Confluence Breakdown -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <ConfluenceCard
        title="Bull Confluence Breakdown"
        :score="bullScore"
        :breakdown="bullBreakdown"
        type="bull"
      />
      <ConfluenceCard
        title="Bear Confluence Breakdown"
        :score="bearScore"
        :breakdown="bearBreakdown"
        type="bear"
      />
    </div>

    <!-- Market Structure Info -->
    <MarketStructureCard
      :activeOrderBlocks="activeOrderBlocks"
      :activeFvgs="activeFvgs"
      :pocLevel="pocLevel"
      :vahLevel="vahLevel"
      :valLevel="valLevel"
      :premiumDiscount="premiumDiscount"
    />

    <!-- Open Positions -->
    <PositionsPanel :positions="positions" @refresh="loadPositions" />

    <!-- Recent Trades -->
    <TradesPanel :trades="trades" />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import api from '../services/api'
import StatCard from './StatCard.vue'
import SignalsPanel from './SignalsPanel.vue'
import FundamentalWidget from './FundamentalWidget.vue'
import ConfluenceCard from './ConfluenceCard.vue'
import MarketStructureCard from './MarketStructureCard.vue'
import PositionsPanel from './PositionsPanel.vue'
import TradesPanel from './TradesPanel.vue'
import StrategyCommander from './StrategyCommander.vue'
import ActivityLog from './ActivityLog.vue'
import RealTimeChart from './RealTimeChart.vue'

// State
const symbol = ref('EURUSD')
const timeframe = ref('H1')
const currentPrice = ref(null)
const trend = ref(null)
const bullScore = ref(0)
const bearScore = ref(0)
const bullBreakdown = ref({})
const bearBreakdown = ref({})
const signals = ref([])
const positions = ref([])
const trades = ref([])
const activeOrderBlocks = ref(0)
const activeFvgs = ref(0)
const pocLevel = ref(null)
const vahLevel = ref(null)
const valLevel = ref(null)
const premiumDiscount = ref({})
const isAnalyzing = ref(false)
const autoRefresh = ref(false)
const lastUpdate = ref(null)
let autoRefreshInterval = null

const trendColor = computed(() => {
  return trend.value === 'BULLISH' ? 'text-emerald-400' : 'text-red-400'
})

async function analyze() {
  if (isAnalyzing.value) return

  isAnalyzing.value = true
  try {
    const result = await api.analyzeMarket(symbol.value, timeframe.value)

    currentPrice.value = result.current_price
    trend.value = result.trend
    bullScore.value = result.bull_confluence_score
    bearScore.value = result.bear_confluence_score
    bullBreakdown.value = result.bull_score_breakdown || {}
    bearBreakdown.value = result.bear_score_breakdown || {}
    signals.value = result.signals || []
    activeOrderBlocks.value = result.active_order_blocks || 0
    activeFvgs.value = result.active_fvgs || 0
    pocLevel.value = result.poc_level
    vahLevel.value = result.vah_level
    valLevel.value = result.val_level
    premiumDiscount.value = result.premium_discount || {}
    lastUpdate.value = new Date().toISOString()

  } catch (error) {
    console.error('Analysis failed:', error)
    alert('Analysis failed. Make sure backend and MT5 are connected.')
  } finally {
    isAnalyzing.value = false
  }
}

async function refresh() {
  await analyze()
  await loadPositions()
  await loadTrades()
}

async function loadPositions() {
  try {
    const result = await api.getPositions()
    positions.value = result.positions || []
  } catch (error) {
    console.error('Failed to load positions:', error)
  }
}

async function loadTrades() {
  try {
    trades.value = await api.getTrades(20)
  } catch (error) {
    console.error('Failed to load trades:', error)
  }
}

function toggleAutoRefresh() {
  autoRefresh.value = !autoRefresh.value

  if (autoRefresh.value) {
    refresh()
    autoRefreshInterval = setInterval(refresh, 10000) // Every 10 seconds
  } else {
    if (autoRefreshInterval) {
      clearInterval(autoRefreshInterval)
      autoRefreshInterval = null
    }
  }
}

async function executeSignal(signal) {
  const confirmed = confirm(
    `Execute ${signal.signal_type} signal?\n\n` +
    `Entry: ${signal.entry_price.toFixed(5)}\n` +
    `Stop Loss: ${signal.stop_loss.toFixed(5)}\n` +
    `Take Profit: ${signal.take_profit_1.toFixed(5)}\n` +
    `Confluence: ${signal.confluence_score}/10`
  )

  if (!confirmed) return

  try {
    await api.openTrade({
      symbol: signal.symbol,
      trade_type: signal.signal_type,
      entry_price: signal.entry_price,
      stop_loss: signal.stop_loss,
      take_profit_1: signal.take_profit_1,
      take_profit_2: signal.take_profit_2,
      take_profit_3: signal.take_profit_3,
      volume: 0.01, // TODO: Calculate based on risk
      risk_percent: 2.0,
      confluence_score: signal.confluence_score,
      score_breakdown: signal.score_breakdown
    })

    alert('Trade opened successfully!')
    await refresh()
  } catch (error) {
    console.error('Failed to execute trade:', error)
    alert('Failed to execute trade. Check console for details.')
  }
}

onMounted(async () => {
  await refresh()
})

onUnmounted(() => {
  if (autoRefreshInterval) {
    clearInterval(autoRefreshInterval)
  }
})
</script>
