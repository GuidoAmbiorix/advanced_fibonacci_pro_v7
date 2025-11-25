<template>
  <div class="min-h-screen bg-slate-900 text-white font-sans flex flex-col">
    <!-- Header -->
    <header class="bg-slate-950 border-b border-slate-800 p-4 flex justify-between items-center shadow-lg z-10">
      <div class="flex items-center space-x-4">
        <div class="text-2xl font-black tracking-tighter text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-emerald-400">
          INSTITUTIONAL EDGE
        </div>
        <div class="px-2 py-1 bg-slate-800 rounded text-xs font-mono text-slate-400 border border-slate-700">
          EXECUTION TERMINAL
        </div>
      </div>

      <div class="flex items-center space-x-6">
        <!-- Symbol Selector -->
        <div class="flex items-center bg-slate-900 rounded-lg p-2 border border-slate-700">
          <span class="text-xs font-bold px-2 text-slate-400">SYMBOL:</span>
          <select v-model="selectedSymbol" @change="onSymbolChange" class="bg-slate-800 text-white text-sm font-bold px-3 py-1 rounded border border-slate-600 focus:outline-none focus:border-blue-500">
            <option v-for="sym in availableSymbols" :key="sym.symbol" :value="sym.symbol">
              {{ sym.symbol }}
            </option>
          </select>
        </div>

        <!-- Bot Control -->
        <div class="flex items-center space-x-2">
          <button 
            @click="toggleBot" 
            class="px-4 py-2 rounded font-bold transition-colors flex items-center"
            :class="isBotRunning ? 'bg-red-600 hover:bg-red-500' : 'bg-emerald-600 hover:bg-emerald-500'"
          >
            <span class="mr-2">{{ isBotRunning ? 'STOP BOT' : 'START BOT' }}</span>
            <span class="relative flex h-3 w-3">
              <span v-if="isBotRunning" class="animate-ping absolute inline-flex h-full w-full rounded-full bg-white opacity-75"></span>
              <span class="relative inline-flex rounded-full h-3 w-3 bg-white"></span>
            </span>
          </button>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main class="flex-1 p-6 grid grid-cols-12 gap-6">
      
      <!-- Left Column: Signals & Execution (4 cols) -->
      <div class="col-span-4 flex flex-col space-y-6">
        <!-- Trading Plan Config -->
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-4 shadow-xl">
          <div class="flex justify-between items-center mb-4">
             <h3 class="text-slate-400 text-xs uppercase tracking-widest font-bold">Trading Plan</h3>
             <button @click="saveConfig" class="text-xs bg-blue-600 hover:bg-blue-500 px-2 py-1 rounded text-white font-bold transition-colors">SAVE</button>
          </div>
          
          <div class="space-y-4">
            <!-- Risk & BE -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="text-xs text-slate-500 block mb-1">Risk per Trade (%)</label>
                <input type="number" v-model.number="tradingPlan.risk_percent" step="0.1" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm focus:border-blue-500 outline-none">
              </div>
              <div>
                <label class="text-xs text-slate-500 block mb-1">BE Trigger (R)</label>
                <input type="number" v-model.number="tradingPlan.be_trigger" step="0.1" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm focus:border-blue-500 outline-none">
              </div>
            </div>

            <!-- Trailing SL -->
            <div class="bg-slate-900/50 p-2 rounded border border-slate-700/50">
              <div class="flex items-center justify-between mb-2">
                <label class="text-xs text-slate-400 font-bold">Trailing Stop Loss</label>
                <input type="checkbox" v-model="tradingPlan.trailing_sl" class="accent-blue-500">
              </div>
              <div v-if="tradingPlan.trailing_sl" class="grid grid-cols-1 gap-2">
                 <div>
                  <label class="text-[10px] text-slate-500 block mb-1">Step (R)</label>
                  <input type="number" v-model.number="tradingPlan.trailing_step" step="0.1" class="w-full bg-slate-800 border border-slate-700 rounded px-2 py-1 text-xs">
                </div>
              </div>
            </div>

            <!-- Partial TP -->
            <div class="bg-slate-900/50 p-2 rounded border border-slate-700/50">
              <div class="flex items-center justify-between mb-2">
                <label class="text-xs text-slate-400 font-bold">Partial Take Profit</label>
                <input type="checkbox" v-model="tradingPlan.partial_tp_on" class="accent-blue-500">
              </div>
              <div v-if="tradingPlan.partial_tp_on" class="grid grid-cols-1 gap-2">
                 <div>
                  <label class="text-[10px] text-slate-500 block mb-1">Amount (0.1 - 1.0)</label>
                  <input type="number" v-model.number="tradingPlan.partial_tp_amount" step="0.1" max="1.0" class="w-full bg-slate-800 border border-slate-700 rounded px-2 py-1 text-xs">
                </div>
              </div>
            </div>

            <!-- Filters -->
             <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="text-xs text-slate-500 block mb-1">Max Spread (Pips)</label>
                <input type="number" v-model.number="tradingPlan.max_spread" step="0.1" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm">
              </div>
              <div>
                <label class="text-xs text-slate-500 block mb-1">Daily Loss Limit (%)</label>
                <input type="number" v-model.number="tradingPlan.daily_loss_limit_percent" step="0.5" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm">
              </div>
            </div>
             <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="text-xs text-slate-500 block mb-1">Start Time</label>
                <input type="time" v-model="tradingPlan.trading_hours_start" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm">
              </div>
              <div>
                <label class="text-xs text-slate-500 block mb-1">End Time</label>
                <input type="time" v-model="tradingPlan.trading_hours_end" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm">
              </div>
            </div>

          </div>
        </div>

        <!-- Signal Feed -->
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-4 shadow-xl flex-1 overflow-hidden flex flex-col">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-slate-400 text-xs uppercase tracking-widest font-bold">Signal Feed</h3>
            <button @click="fetchSignals" class="text-xs text-blue-400 hover:text-blue-300">Refresh</button>
          </div>
          
          <div class="overflow-y-auto flex-1 space-y-3 pr-2">
            <div v-for="signal in signals" :key="signal.id" class="bg-slate-900/50 border border-slate-700 rounded-lg p-3 hover:border-slate-500 transition-colors">
              <div class="flex justify-between items-start mb-2">
                <div>
                  <span class="font-black text-lg" :class="signal.signal_type === 'BUY' ? 'text-emerald-400' : 'text-red-400'">
                    {{ signal.signal_type }}
                  </span>
                  <span class="text-slate-400 text-sm ml-2">{{ signal.symbol }}</span>
                </div>
                <div class="text-xs text-slate-500">{{ formatTimeAgo(signal.created_at) }}</div>
              </div>
              
              <div class="grid grid-cols-2 gap-2 text-sm mb-3">
                <div class="flex justify-between">
                  <span class="text-slate-500">Entry:</span>
                  <span class="font-mono">{{ signal.price }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-500">SL:</span>
                  <span class="font-mono text-red-400">{{ signal.stop_loss }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-500">TP1:</span>
                  <span class="font-mono text-emerald-400">{{ signal.take_profit }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-500">Conf:</span>
                  <span class="font-bold text-yellow-400">{{ signal.confluence_score }}/10</span>
                </div>
              </div>

              <button 
                v-if="!signal.was_executed"
                @click="executeSignal(signal)"
                class="w-full py-2 rounded font-bold text-sm bg-blue-600 hover:bg-blue-500 transition-colors"
              >
                EXECUTE NOW
              </button>
              <div v-else class="text-center text-xs text-slate-500 font-mono py-2 bg-slate-900 rounded">
                EXECUTED
              </div>
            </div>
            
            <div v-if="signals.length === 0" class="text-center text-slate-500 py-8">
              No recent signals found
            </div>
          </div>
        </div>
      </div>

      <!-- Center & Right: Chart & Trades (8 cols) -->
      <div class="col-span-8 flex flex-col space-y-6">
        <!-- Chart Area -->
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-4 shadow-xl h-96 relative">
           <div class="w-full h-full">
            <Line
              v-if="chartData.datasets.length > 0"
              :data="chartData"
              :options="chartOptions"
            />
            <div v-else class="flex items-center justify-center h-full text-slate-500">
              Loading Chart Data...
            </div>
          </div>
        </div>

        <!-- Open Trades -->
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-4 shadow-xl flex-1">
          <h3 class="text-slate-400 text-xs uppercase tracking-widest mb-4 font-bold">Open Positions</h3>
          <div class="overflow-x-auto">
            <table class="w-full text-sm text-left">
              <thead class="text-xs text-slate-500 uppercase bg-slate-900/50">
                <tr>
                  <th class="px-4 py-3">Ticket</th>
                  <th class="px-4 py-3">Symbol</th>
                  <th class="px-4 py-3">Type</th>
                  <th class="px-4 py-3">Volume</th>
                  <th class="px-4 py-3">Entry</th>
                  <th class="px-4 py-3">Current</th>
                  <th class="px-4 py-3">PnL</th>
                  <th class="px-4 py-3">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="trade in openTrades" :key="trade.ticket" class="border-b border-slate-700 hover:bg-slate-700/50">
                  <td class="px-4 py-3 font-mono">{{ trade.ticket }}</td>
                  <td class="px-4 py-3 font-bold">{{ trade.symbol }}</td>
                  <td class="px-4 py-3" :class="trade.type === 'BUY' ? 'text-emerald-400' : 'text-red-400'">{{ trade.type }}</td>
                  <td class="px-4 py-3">{{ trade.volume }}</td>
                  <td class="px-4 py-3 font-mono">{{ trade.entry }}</td>
                  <td class="px-4 py-3 font-mono">{{ trade.current }}</td>
                  <td class="px-4 py-3 font-mono font-bold" :class="trade.pnl >= 0 ? 'text-emerald-400' : 'text-red-400'">
                    {{ formatCurrency(trade.pnl) }}
                  </td>
                  <td class="px-4 py-3">
                    <button class="text-xs bg-slate-700 hover:bg-slate-600 px-2 py-1 rounded mr-2">BE</button>
                    <button class="text-xs bg-red-900/50 hover:bg-red-900 text-red-400 px-2 py-1 rounded">CLOSE</button>
                  </td>
                </tr>
                 <tr v-if="openTrades.length === 0">
                  <td colspan="8" class="px-4 py-8 text-center text-slate-500">No open positions</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { Line } from 'vue-chartjs';
import { Chart as ChartJS, CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler } from 'chart.js';
import api from '../services/api';

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler);

// State
const selectedSymbol = ref('EURUSD');
const availableSymbols = ref([]);
const isBotRunning = ref(false);
const signals = ref([]);
const openTrades = ref([]);
const tradingPlan = ref({
  risk_percent: 2.0,
  be_trigger: 1.0,
  trailing_sl: false,
  trailing_step: 1.0,
  partial_tp_on: false,
  partial_tp_amount: 0.5,
  max_spread: 2.0,
  trading_hours_start: "00:00",
  trading_hours_end: "23:59",
  daily_loss_limit_percent: 3.0
});

// Chart State
const chartData = ref({ labels: [], datasets: [] });
const chartOptions = ref({
  responsive: true,
  maintainAspectRatio: false,
  scales: {
    y: { grid: { color: '#334155' }, ticks: { color: '#94a3b8' } },
    x: { display: false }
  },
  plugins: { legend: { display: false } },
  elements: { point: { radius: 0 }, line: { tension: 0.1 } }
});

// Methods
const loadSymbols = async () => {
  try {
    const data = await api.getSymbols();
    if (data.symbols) availableSymbols.value = data.symbols;
  } catch (e) { console.error(e); }
};

const loadConfig = async () => {
  try {
    const config = await api.getBotConfig(1); // Default ID 1
    if (config) {
      tradingPlan.value = {
        risk_percent: config.risk_percent,
        be_trigger: config.be_trigger,
        trailing_sl: config.trailing_sl,
        trailing_step: config.trailing_step,
        partial_tp_on: config.partial_tp_on,
        partial_tp_amount: config.partial_tp_amount,
        max_spread: config.max_spread,
        trading_hours_start: config.trading_hours_start,
        trading_hours_end: config.trading_hours_end,
        daily_loss_limit_percent: config.daily_loss_limit_percent
      };
    }
  } catch (e) { console.error("Error loading config:", e); }
};

const saveConfig = async () => {
  try {
    await api.updateBotConfig(1, tradingPlan.value);
    alert("Configuration Saved!");
  } catch (e) {
    console.error("Error saving config:", e);
    alert("Failed to save configuration");
  }
};

const fetchSignals = async () => {
  try {
    const data = await api.getSignals(selectedSymbol.value);
    if (data.signals) signals.value = data.signals;
  } catch (e) { console.error(e); }
};

const fetchTrades = async () => {
  // TODO: Implement getOpenTrades endpoint or filter from getTrades
  // For now, mocking or using getTrades
  try {
    const trades = await api.getTrades(10, 'OPEN');
    openTrades.value = trades.map(t => ({
      ticket: t.ticket,
      symbol: t.symbol,
      type: t.trade_type,
      volume: t.volume,
      entry: t.entry_price,
      current: t.entry_price, // Mock current price for now
      pnl: t.profit_loss || 0
    }));
  } catch (e) { console.error(e); }
};

const updateChart = async () => {
  try {
    const history = await api.getMarketHistory(selectedSymbol.value, "H1", 100);
    if (history && history.data) {
      const prices = history.data.map(d => d.close);
      const labels = history.data.map(d => new Date(d.time).toLocaleTimeString());
      
      chartData.value = {
        labels,
        datasets: [{
          label: selectedSymbol.value,
          data: prices,
          borderColor: '#10b981',
          backgroundColor: 'rgba(16, 185, 129, 0.1)',
          fill: true,
          borderWidth: 2
        }]
      };
    }
  } catch (e) { console.error(e); }
};

const toggleBot = async () => {
  try {
    const botId = 1; // Default bot
    if (isBotRunning.value) {
      await api.stopBot(botId);
      isBotRunning.value = false;
    } else {
      await api.startBot(botId);
      isBotRunning.value = true;
    }
  } catch (e) { console.error(e); }
};

const executeSignal = async (signal) => {
  if (!confirm(`Execute ${signal.signal_type} on ${signal.symbol}?`)) return;
  
  try {
    await api.openTrade({
      symbol: signal.symbol,
      trade_type: signal.signal_type,
      volume: 0.01, // Default or calc
      stop_loss: signal.stop_loss,
      take_profit_1: signal.take_profit,
      risk_percent: tradingPlan.value.risk_percent,
      confluence_score: signal.confluence_score,
      score_breakdown: signal.score_breakdown
    });
    alert('Trade Executed!');
    fetchSignals(); // Refresh to show executed status
  } catch (e) {
    alert('Execution Failed: ' + e.message);
  }
};

const onSymbolChange = () => {
  fetchSignals();
  updateChart();
};

const formatTimeAgo = (iso) => {
  if (!iso) return '';
  const date = new Date(iso);
  const diff = (new Date() - date) / 1000;
  if (diff < 60) return `${Math.floor(diff)}s ago`;
  if (diff < 3600) return `${Math.floor(diff/60)}m ago`;
  return `${Math.floor(diff/3600)}h ago`;
};

const formatCurrency = (val) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(val);

// Lifecycle
let pollInterval;
onMounted(() => {
  loadSymbols();
  loadConfig();
  fetchSignals();
  updateChart();
  fetchTrades();
  
  pollInterval = setInterval(() => {
    fetchSignals();
    fetchTrades();
    if (isBotRunning.value) updateChart(); // Only update chart frequently if active
  }, 5000);
});

onUnmounted(() => {
  clearInterval(pollInterval);
});
</script>
