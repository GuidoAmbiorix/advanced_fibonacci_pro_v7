<template>
  <div
    class="min-h-screen bg-slate-900 text-white font-sans overflow-hidden flex flex-col relative"
  >
    <!-- Execution Alert Overlay -->
    <div
      v-if="executionAlert"
      class="absolute inset-0 z-50 bg-slate-900/90 flex items-center justify-center backdrop-blur-sm animate-in fade-in duration-300"
    >
      <div class="text-center animate-bounce-in">
        <div class="text-6xl mb-4">🚀</div>
        <h2
          class="text-5xl font-black text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-emerald-400 mb-2"
        >
          ORDER EXECUTED
        </h2>
        <div class="text-3xl text-white font-bold">
          {{ executionAlert.type }} {{ executionAlert.symbol }}
        </div>
        <div class="text-xl text-slate-400 mt-2">
          @ {{ executionAlert.price }}
        </div>
      </div>
    </div>

    <!-- Broadcast Header -->
    <header
      class="bg-slate-950 border-b border-slate-800 p-4 flex justify-between items-center shadow-lg z-10"
    >
      <div class="flex items-center space-x-4">
        <div class="relative">
          <div
            class="w-3 h-3 bg-red-500 rounded-full animate-pulse absolute top-0 right-0 -mt-1 -mr-1"
          ></div>
          <div
            class="text-2xl font-black tracking-tighter text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-emerald-400"
          >
            QUANTUM EDGE
          </div>
        </div>
        <div
          class="px-2 py-1 bg-slate-800 rounded text-xs font-mono text-slate-400 border border-slate-700"
        >
          LIVE MARKET SCAN
        </div>
      </div>

      <div class="flex items-center space-x-6">
        <!-- Symbol Selector -->
        <div class="flex items-center bg-slate-900 rounded-lg p-2 border border-slate-700">
          <span class="text-xs font-bold px-2 text-slate-400">SYMBOL:</span>
          <select
            v-model="selectedSymbol"
            @change="onSymbolChange"
            class="bg-slate-800 text-white text-sm font-bold px-3 py-1 rounded border border-slate-600 focus:outline-none focus:border-blue-500"
          >
            <option v-for="sym in availableSymbols" :key="sym.symbol" :value="sym.symbol">
              {{ sym.symbol }} ({{ sym.symbol_type }})
            </option>
          </select>
        </div>

        <!-- Auto-Trade Toggle -->
        <div
          class="flex items-center bg-slate-900 rounded-full p-1 border border-slate-700"
        >
          <span class="text-xs font-bold px-3 text-slate-400">AUTO-TRADE</span>
          <button
            @click="toggleAutoTrade"
            class="relative w-12 h-6 rounded-full transition-colors duration-300 focus:outline-none"
            :class="isAutoTradeEnabled ? 'bg-emerald-500' : 'bg-slate-700'"
          >
            <div
              class="absolute top-1 left-1 w-4 h-4 bg-white rounded-full shadow-md transition-transform duration-300"
              :class="isAutoTradeEnabled ? 'translate-x-6' : 'translate-x-0'"
            ></div>
          </button>
        </div>

        <div class="text-right">
          <div class="text-xs text-slate-500 uppercase tracking-widest">
            System Status
          </div>
          <div class="text-emerald-400 font-bold flex items-center justify-end">
            <span
              class="w-2 h-2 bg-emerald-500 rounded-full mr-2 animate-pulse"
            ></span>
            OPERATIONAL
          </div>
        </div>
        <div class="text-right">
          <div class="text-xs text-slate-500 uppercase tracking-widest">
            Active Strategy
          </div>
          <div class="text-white font-bold">{{ selectedSymbol }} / H1</div>
        </div>
      </div>
    </header>

    <!-- Main Content Grid -->
    <main class="flex-1 p-6 grid grid-cols-12 gap-6 relative">
      <!-- Background Grid Effect -->
      <div
        class="absolute inset-0 opacity-5 pointer-events-none"
        style="
          background-image: radial-gradient(#4f46e5 1px, transparent 1px);
          background-size: 30px 30px;
        "
      ></div>

      <!-- Left Column: Signal & Performance (4 cols) -->
      <div class="col-span-3 flex flex-col space-y-6 z-10">
        <!-- Active Signal Card -->
        <div
          class="bg-slate-800/50 backdrop-blur-md border border-slate-700 rounded-xl p-6 shadow-2xl relative overflow-hidden group"
        >
          <div
            class="absolute top-0 left-0 w-1 h-full bg-gradient-to-b from-blue-500 to-purple-500"
          ></div>

          <h3 class="text-slate-400 text-sm uppercase tracking-widest mb-4">
            Latest Signal
          </h3>

          <div v-if="lastSignal" class="space-y-4">
            <div class="flex justify-between items-end">
              <div
                :class="
                  lastSignal.type === 'BUY'
                    ? 'text-emerald-400'
                    : 'text-red-400'
                "
                class="text-5xl font-black tracking-tighter"
              >
                {{ lastSignal.type }}
              </div>
              <div class="text-2xl font-bold text-white mb-1">
                {{ lastSignal.symbol }}
              </div>
            </div>

            <div class="grid grid-cols-2 gap-4 mt-4">
              <div class="bg-slate-900/50 p-3 rounded-lg">
                <div class="text-xs text-slate-500">Entry</div>
                <div class="text-lg font-mono font-bold">
                  {{ formatPrice(lastSignal.price) }}
                </div>
              </div>
              <div class="bg-slate-900/50 p-3 rounded-lg">
                <div class="text-xs text-slate-500">Confluence</div>
                <div class="text-lg font-mono font-bold text-yellow-400">
                  {{ lastSignal.score }}/10
                </div>
              </div>
            </div>

            <!-- AI Confidence Score -->
            <div v-if="lastSignal.aiConfidence > 0" class="mt-4 bg-gradient-to-r from-purple-900/30 to-blue-900/30 p-3 rounded-lg border border-purple-500/30">
              <div class="flex justify-between items-center">
                <div class="text-xs text-purple-300 flex items-center">
                  <span class="mr-2">🤖</span>
                  AI Confidence
                </div>
                <div class="text-sm font-bold" :class="getAIConfidenceColor(lastSignal.aiConfidence)">
                  {{ lastSignal.aiConfidence.toFixed(1) }}%
                </div>
              </div>
              <div class="mt-2 bg-slate-800/50 rounded-full h-2">
                <div class="h-full rounded-full transition-all"
                     :class="getAIConfidenceColor(lastSignal.aiConfidence)"
                     :style="`width: ${lastSignal.aiConfidence}%`">
                </div>
              </div>
              <div class="text-xs text-slate-400 mt-1 text-center">
                {{ lastSignal.aiRecommendation }}
              </div>
            </div>

            <!-- Confluence Breakdown Mini -->
            <div class="space-y-1 mt-2">
              <div
                v-for="(score, factor) in lastSignal.breakdown"
                :key="factor"
                class="flex justify-between text-xs"
              >
                <span class="text-slate-400">{{ factor }}</span>
                <span class="text-slate-200">+{{ score }}</span>
              </div>
            </div>
          </div>

          <div
            v-else
            class="h-48 flex flex-col items-center justify-center text-slate-500"
          >
            <div
              class="w-12 h-12 border-4 border-slate-700 border-t-blue-500 rounded-full animate-spin mb-4"
              v-if="botStatus.isScanning"
            ></div>
            <div
              class="w-12 h-12 border-4 border-slate-700 border-slate-600 rounded-full mb-4"
              v-else
            ></div>
            <span class="animate-pulse" v-if="isAutoTradeEnabled"
              >Scanning for High-Probability Setups...</span
            >
            <span v-else class="text-slate-400"
              >Auto-trade disabled</span
            >
            <span class="text-xs text-slate-600 mt-2"
              >Min. Confluence Score: 6/10</span
            >
            <div v-if="botStatus.lastScanTime" class="text-xs text-slate-500 mt-3">
              <div>Last scan: {{ formatTimeAgo(botStatus.lastScanTime) }}</div>
              <div v-if="botStatus.nextScanIn && isAutoTradeEnabled" class="text-blue-400 mt-1">
                Next scan in: {{ botStatus.nextScanIn }}s
              </div>
            </div>
          </div>
        </div>

        <!-- Session Stats -->
        <div
          class="bg-slate-800/50 backdrop-blur-md border border-slate-700 rounded-xl p-6 shadow-xl"
        >
          <h3 class="text-slate-400 text-sm uppercase tracking-widest mb-4">
            Session Performance
          </h3>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <div class="text-xs text-slate-500">Trades Today</div>
              <div class="text-2xl font-bold text-white">
                {{ stats.trades }}
              </div>
            </div>
            <div>
              <div class="text-xs text-slate-500">Win Rate</div>
              <div class="text-2xl font-bold text-emerald-400">
                {{ stats.winRate }}%
              </div>
            </div>
            <div class="col-span-2 pt-4 border-t border-slate-700">
              <div class="text-xs text-slate-500">Net PnL (Session)</div>
              <div
                :class="stats.pnl >= 0 ? 'text-emerald-400' : 'text-red-400'"
                class="text-3xl font-black tracking-tight transition-colors duration-500"
              >
                <span v-if="privacyMode">****</span>
                <span v-else>{{ formatCurrency(stats.pnl) }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Center Column: Main Chart (6 cols) -->
      <div class="col-span-6 flex flex-col z-10">
        <div
          class="bg-slate-800/80 backdrop-blur-md border border-slate-700 rounded-xl flex-1 shadow-2xl relative overflow-hidden p-4"
        >
          <div class="w-full h-full">
            <Line
              v-if="chartData.datasets.length > 0"
              :data="chartData"
              :options="chartOptions"
            />
            <div
              v-else
              class="flex items-center justify-center h-full text-slate-500"
            >
              <span
                v-if="chartError"
                class="text-red-400 flex flex-col items-center"
              >
                <div class="flex items-center mb-2">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-6 h-6 mr-2"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z"
                    />
                  </svg>
                  {{ chartError }}
                </div>
                <button
                  @click="updateChart"
                  class="px-3 py-1 bg-slate-700 hover:bg-slate-600 rounded text-xs text-white transition-colors"
                >
                  🔄 Retry Connection
                </button>
              </span>
              <span v-else class="animate-pulse">Loading Chart Data...</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Right Column: Market Pulse (3 cols) -->
      <div class="col-span-3 flex flex-col space-y-6 z-10">
        <!-- Market Pulse Cards -->
        <div
          class="bg-slate-800/50 backdrop-blur-md border border-slate-700 rounded-xl p-6 shadow-xl"
        >
          <h3 class="text-slate-400 text-sm uppercase tracking-widest mb-4">
            Market Pulse
          </h3>

          <div class="space-y-6">
            <!-- Trend -->
            <div>
              <div class="flex justify-between mb-2">
                <span class="text-sm text-slate-300">Major Trend (H1)</span>
                <span
                  class="text-sm font-bold"
                  :class="
                    marketPulse.trend === 'BULLISH'
                      ? 'text-emerald-400'
                      : marketPulse.trend === 'BEARISH'
                      ? 'text-red-400'
                      : 'text-slate-400'
                  "
                >
                  {{ marketPulse.trend }}
                </span>
              </div>
              <div class="h-2 bg-slate-700 rounded-full overflow-hidden">
                <div
                  class="h-full transition-all duration-1000"
                  :class="
                    marketPulse.trend === 'BULLISH'
                      ? 'bg-emerald-500'
                      : marketPulse.trend === 'BEARISH'
                      ? 'bg-red-500'
                      : 'bg-slate-500'
                  "
                  :style="`width: ${marketPulse.trendStrength}%`"
                ></div>
              </div>
            </div>

            <!-- Current Price -->
            <div>
              <div class="flex justify-between mb-2">
                <span class="text-sm text-slate-300">Current Price</span>
                <span class="text-sm font-bold text-blue-400 font-mono">{{
                  formatPrice(currentPrice)
                }}</span>
              </div>
              <div class="text-xs text-slate-500">Live from MT5</div>
            </div>

            <!-- Active OBs & FVGs -->
            <div>
              <div class="flex justify-between mb-2">
                <span class="text-sm text-slate-300">Active Structures</span>
                <span class="text-sm font-bold text-yellow-400">{{
                  marketPulse.activeStructures || 0
                }}</span>
              </div>
              <div class="text-xs text-slate-500">Order Blocks & FVGs</div>
            </div>
          </div>
        </div>

        <!-- Recent Trades List -->
        <div
          class="bg-slate-800/50 backdrop-blur-md border border-slate-700 rounded-xl p-6 shadow-xl flex-1 overflow-hidden"
        >
          <h3 class="text-slate-400 text-sm uppercase tracking-widest mb-4">
            Recent Executions
          </h3>
          <div class="space-y-3">
            <div
              v-for="trade in recentTrades"
              :key="trade.id"
              class="flex justify-between items-center p-3 bg-slate-900/50 rounded-lg border border-slate-800"
            >
              <div>
                <div
                  class="font-bold"
                  :class="
                    trade.type === 'BUY' ? 'text-emerald-400' : 'text-red-400'
                  "
                >
                  {{ trade.type }} {{ trade.symbol }}
                </div>
                <div class="text-xs text-slate-500">{{ trade.time }}</div>
              </div>
              <div class="text-right">
                <div
                  class="font-mono font-bold"
                  :class="trade.pnl >= 0 ? 'text-emerald-400' : 'text-red-400'"
                >
                  <span v-if="privacyMode">****</span>
                  <span v-else
                    >{{ trade.pnl >= 0 ? "+" : ""
                    }}{{ formatCurrency(trade.pnl) }}</span
                  >
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>

    <!-- Scrolling Ticker Footer -->
    <footer
      class="bg-slate-950 border-t border-slate-800 h-10 flex items-center overflow-hidden whitespace-nowrap relative"
    >
      <div
        class="animate-marquee flex space-x-8 text-sm font-mono text-slate-400"
      >
        <span v-for="i in 5" :key="i" class="flex items-center space-x-2">
          <span class="text-blue-500 font-bold">INFO</span>
          <span>QUANTUM EDGE SYSTEM ACTIVE</span>
          <span class="text-slate-600">|</span>
          <span class="text-emerald-500 font-bold">BTCUSD</span>
          <span>$42,150.50</span>
          <span class="text-emerald-500">(+1.2%)</span>
          <span class="text-slate-600">|</span>
          <span class="text-yellow-500 font-bold">NEXT NEWS</span>
          <span>FOMC MEETING IN 2H 15M</span>
          <span class="text-slate-600">|</span>
        </span>
      </div>
    </footer>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from "vue";
import { Line } from "vue-chartjs";
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from "chart.js";
import api from "../services/api";

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
);

const props = defineProps({
  privacyMode: {
    type: Boolean,
    default: false,
  },
});

// Auto-Trade State
const isAutoTradeEnabled = ref(false);
const executionAlert = ref(null);
const botStatus = ref({
  lastScanTime: null,
  nextScanIn: null,
  isScanning: false,
});

// Symbol management
const availableSymbols = ref([]);
const selectedSymbol = ref('BTCUSD');
const selectedSymbolType = ref('crypto');

async function toggleAutoTrade() {
  isAutoTradeEnabled.value = !isAutoTradeEnabled.value;
  const botId = 1; // Bitcoin Alpha bot

  try {
    if (isAutoTradeEnabled.value) {
      await api.startBot(botId);

      // Monitor for new trades (check every 2 seconds)
      const checkForNewTrades = setInterval(async () => {
        if (!isAutoTradeEnabled.value) {
          clearInterval(checkForNewTrades);
          return;
        }

        try {
          const trades = await api.getTrades(1);
          if (trades && trades.length > 0) {
            const latestTrade = trades[0];
            // Check if this is a new trade (less than 5 seconds old)
            const tradeTime = new Date(latestTrade.opened_at);
            const now = new Date();
            const diffSeconds = (now - tradeTime) / 1000;

            if (diffSeconds < 5) {
              triggerExecutionAlert({
                type: latestTrade.trade_type,
                symbol: latestTrade.symbol,
                price: latestTrade.entry_price,
              });
              clearInterval(checkForNewTrades);
            }
          }
        } catch (e) {
          console.error("Failed to check for new trades", e);
        }
      }, 2000);
    } else {
      await api.stopBot(botId);
    }
  } catch (e) {
    console.error("Failed to toggle auto-trade", e);
    // Revert state if failed
    isAutoTradeEnabled.value = !isAutoTradeEnabled.value;
  }
}

function triggerExecutionAlert(trade) {
  executionAlert.value = trade;
  setTimeout(() => {
    executionAlert.value = null;
  }, 3000);
}

// Real Data from API
const lastSignal = ref(null);
const stats = ref({
  trades: 0,
  winRate: 0,
  pnl: 0,
});
const recentTrades = ref([]);
const currentPrice = ref(0);
const marketPulse = ref({
  trend: "NEUTRAL",
  trendStrength: 50,
  rsi: 50,
  volatility: "MODERATE",
  volatilityPercent: 50,
  activeStructures: 0,
});

// Load available symbols
async function loadSymbols() {
  try {
    const data = await api.getSymbols();
    if (data && data.symbols && data.symbols.length > 0) {
      availableSymbols.value = data.symbols;
      // Set initial selected symbol to first crypto or first symbol
      const cryptoSymbol = data.symbols.find(s => s.symbol_type === 'crypto');
      if (cryptoSymbol) {
        selectedSymbol.value = cryptoSymbol.symbol;
        selectedSymbolType.value = cryptoSymbol.symbol_type;
      } else {
        selectedSymbol.value = data.symbols[0].symbol;
        selectedSymbolType.value = data.symbols[0].symbol_type;
      }
    }
  } catch (e) {
    console.error("Failed to load symbols", e);
  }
}

// Handle symbol change
function onSymbolChange() {
  const selected = availableSymbols.value.find(s => s.symbol === selectedSymbol.value);
  if (selected) {
    selectedSymbolType.value = selected.symbol_type;
    // Refresh all data for the new symbol
    updateChart();
    fetchAnalysis();
  }
}

// Fetch signals from database (generated by bot)
async function fetchSignals() {
  try {
    const data = await api.getSignals(selectedSymbol.value, 1);

    if (data && data.signals && data.signals.length > 0) {
      const signal = data.signals[0];
      lastSignal.value = {
        type: signal.signal_type,
        symbol: signal.symbol,
        price: signal.price,
        score: signal.confluence_score,
        breakdown: signal.score_breakdown || {},
        timestamp: signal.created_at,
        aiConfidence: signal.ai_confidence || 0,
        aiRecommendation: signal.ai_recommendation || 'UNCERTAIN',
      };
    }
  } catch (e) {
    console.error("Failed to fetch signals", e);
  }
}

// Get AI confidence color based on value
function getAIConfidenceColor(confidence) {
  if (confidence >= 75) return 'text-green-400 bg-green-500';
  if (confidence >= 60) return 'text-blue-400 bg-blue-500';
  if (confidence >= 45) return 'text-yellow-400 bg-yellow-500';
  if (confidence >= 30) return 'text-orange-400 bg-orange-500';
  return 'text-red-400 bg-red-500';
}

// Fetch market analysis for market pulse data
async function fetchAnalysis() {
  try {
    const analysis = await api.analyzeMarket(selectedSymbol.value, "H1", selectedSymbolType.value);

    // Update market pulse
    if (analysis) {
      currentPrice.value = analysis.current_price;
      const activeOBs = analysis.active_order_blocks || 0;
      const activeFVGs = analysis.active_fvgs || 0;

      marketPulse.value = {
        trend: analysis.trend || "NEUTRAL",
        trendStrength:
          analysis.trend === "BULLISH"
            ? 75
            : analysis.trend === "BEARISH"
            ? 25
            : 50,
        rsi: 58.4, // You can add RSI to backend analysis
        volatility: "MODERATE",
        volatilityPercent: 50,
        activeStructures: activeOBs + activeFVGs,
      };
    }
  } catch (e) {
    console.error("Failed to fetch analysis", e);
  }
}

// Fetch real trades from database
async function fetchTrades() {
  try {
    const trades = await api.getTrades(10);
    if (trades && trades.length > 0) {
      recentTrades.value = trades.map((t) => ({
        id: t.id,
        type: t.trade_type,
        symbol: t.symbol,
        time: new Date(t.opened_at).toLocaleTimeString(),
        pnl: t.profit_loss || 0,
      }));

      // Calculate stats
      const closedTrades = trades.filter((t) => t.status === "CLOSED");
      stats.value.trades = closedTrades.length;

      if (closedTrades.length > 0) {
        const winners = closedTrades.filter(
          (t) => (t.profit_loss || 0) > 0
        ).length;
        stats.value.winRate = Math.round((winners / closedTrades.length) * 100);
        stats.value.pnl = closedTrades.reduce(
          (sum, t) => sum + (t.profit_loss || 0),
          0
        );
      }
    }
  } catch (e) {
    console.error("Failed to fetch trades", e);
  }
}

const formatCurrency = (value) => {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(value);
};

const formatPrice = (value) => {
  return new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
};

const formatTimeAgo = (isoTimestamp) => {
  if (!isoTimestamp) return 'never';
  const date = new Date(isoTimestamp);
  const seconds = Math.floor((new Date() - date) / 1000);

  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
};

// Update countdown timer
let countdownInterval = null;
const SCAN_INTERVAL_SECONDS = 300; // 5 minutes for H1

function updateCountdown() {
  if (!botStatus.value.lastScanTime || !isAutoTradeEnabled.value) {
    botStatus.value.nextScanIn = null;
    return;
  }

  const lastScan = new Date(botStatus.value.lastScanTime);
  const nextScan = new Date(lastScan.getTime() + SCAN_INTERVAL_SECONDS * 1000);
  const now = new Date();
  const secondsUntilNext = Math.max(0, Math.floor((nextScan - now) / 1000));

  botStatus.value.nextScanIn = secondsUntilNext;

  // Mark as scanning if within 5 seconds of next scan
  botStatus.value.isScanning = secondsUntilNext <= 5;
}

// Chart State
const chartData = ref({
  labels: [],
  datasets: [],
});

const chartOptions = ref({
  responsive: true,
  maintainAspectRatio: false,
  scales: {
    y: {
      grid: { color: "#334155" },
      ticks: { color: "#94a3b8" },
    },
    x: {
      grid: { display: false },
      ticks: { display: false },
    },
  },
  plugins: {
    legend: { display: false },
    tooltip: {
      mode: "index",
      intersect: false,
      backgroundColor: "#1e293b",
      titleColor: "#f8fafc",
      bodyColor: "#f8fafc",
      borderColor: "#334155",
      borderWidth: 1,
    },
  },
  elements: {
    point: { radius: 0, hoverRadius: 4 },
    line: { tension: 0.1 },
  },
});

const chartError = ref(null);
let chartInterval = null;
let websocket = null;

async function updateChart() {
  try {
    const history = await api.getMarketHistory(selectedSymbol.value, "H1", 100, selectedSymbolType.value);
    if (history && history.data) {
      chartError.value = null;
      const prices = history.data.map((d) => d.close);
      const labels = history.data.map((d) =>
        new Date(d.time).toLocaleTimeString()
      );

      chartData.value = {
        labels: labels,
        datasets: [
          {
            label: selectedSymbol.value,
            data: prices,
            borderColor: "#10b981",
            backgroundColor: "rgba(16, 185, 129, 0.1)",
            fill: true,
            borderWidth: 2,
          },
        ],
      };
    }
  } catch (e) {
    console.error("Failed to update chart", e);
    chartError.value =
      "Failed to load chart data. Backend restart may be required.";
  }
}

let analysisInterval = null;
let tradesInterval = null;
let signalsInterval = null;

// WebSocket connection for real-time updates
function connectWebSocket() {
  websocket = api.createWebSocket(
    (message) => {
      // Handle incoming WebSocket messages
      if (message.type === 'status_update') {
        // Update bot status
        const data = message.data;
        if (data.running_bots && data.running_bots.length > 0) {
          const botInfo = data.running_bots.find(b => b.symbol === selectedSymbol.value);
          if (botInfo && botInfo.last_signal_time) {
            botStatus.value.lastScanTime = botInfo.last_signal_time;
          }
        }
        console.log('Status update:', data);
      } else if (message.type === 'trade_executed') {
        // Update last scan time
        botStatus.value.lastScanTime = message.data.timestamp;

        // Show trade execution popup
        triggerExecutionAlert({
          type: message.data.signal_type,
          symbol: message.data.symbol,
          price: message.data.entry_price,
        });
        // Refresh trades and signals
        fetchTrades();
        fetchSignals();
      }
    },
    (error) => {
      console.error('WebSocket error:', error);
    }
  );
}

onMounted(async () => {
  // Load available symbols first
  await loadSymbols();

  // Initial fetch
  updateChart();
  fetchSignals();  // Fetch signals from DB
  fetchAnalysis(); // Fetch market analysis
  fetchTrades();

  // Connect WebSocket for real-time updates
  connectWebSocket();

  // Set up intervals for real-time updates
  chartInterval = setInterval(updateChart, 5000); // Update chart every 5 seconds
  signalsInterval = setInterval(fetchSignals, 5000); // Update signals every 5 seconds
  analysisInterval = setInterval(fetchAnalysis, 10000); // Update analysis every 10 seconds
  tradesInterval = setInterval(fetchTrades, 3000); // Update trades every 3 seconds
  countdownInterval = setInterval(updateCountdown, 1000); // Update countdown every second
});

onUnmounted(() => {
  if (chartInterval) clearInterval(chartInterval);
  if (signalsInterval) clearInterval(signalsInterval);
  if (analysisInterval) clearInterval(analysisInterval);
  if (tradesInterval) clearInterval(tradesInterval);
  if (countdownInterval) clearInterval(countdownInterval);
  if (websocket) websocket.close();
});
</script>

<style scoped>
.animate-marquee {
  animation: marquee 20s linear infinite;
}

@keyframes marquee {
  0% {
    transform: translateX(0);
  }
  100% {
    transform: translateX(-50%);
  }
}

.animate-in {
  animation: fadeIn 0.3s ease-out forwards;
}

.animate-bounce-in {
  animation: bounceIn 0.5s cubic-bezier(0.68, -0.55, 0.265, 1.55) forwards;
}

@keyframes fadeIn {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

@keyframes bounceIn {
  0% {
    transform: scale(0.3);
    opacity: 0;
  }
  50% {
    transform: scale(1.05);
    opacity: 1;
  }
  70% {
    transform: scale(0.9);
  }
  100% {
    transform: scale(1);
  }
}
</style>
