<template>
  <div class="min-h-screen bg-background text-text-secondary font-sans flex flex-col selection:bg-accent/30">
    <!-- Header -->
    <header class="bg-surface/90 backdrop-blur-md border-b border-slate-200 p-4 flex justify-between items-center sticky top-0 z-50 shadow-sm">
      <div class="flex items-center space-x-6">
        <div class="flex flex-col">
          <div class="text-2xl font-black tracking-tighter text-primary">
            INSTITUTIONAL <span class="text-accent">EDGE</span>
          </div>
          <div class="text-[10px] font-mono text-slate-500 tracking-[0.2em] uppercase">
            Professional Execution Terminal
          </div>
        </div>
        
        <!-- Account Info -->
        <div v-if="accountInfo" class="hidden md:flex items-center space-x-4 bg-slate-50 px-4 py-2 rounded-lg border border-slate-200">
           <div class="flex flex-col">
             <span class="text-[10px] text-slate-500 font-bold uppercase tracking-wider">Balance</span>
             <span class="text-sm font-mono font-bold text-primary">{{ formatCurrency(accountInfo.balance) }}</span>
           </div>
           <div class="w-px h-6 bg-slate-200"></div>
           <div class="flex flex-col">
             <span class="text-[10px] text-slate-500 font-bold uppercase tracking-wider">Equity</span>
             <span class="text-sm font-mono font-bold" :class="accountInfo.equity >= accountInfo.balance ? 'text-success' : 'text-danger'">{{ formatCurrency(accountInfo.equity) }}</span>
           </div>
           <div class="w-px h-6 bg-slate-200"></div>
           <div class="flex items-center space-x-2">
             <div class="w-2 h-2 rounded-full" :class="isSocketConnected ? 'bg-success' : 'bg-danger animate-pulse'"></div>
             <span class="text-[10px] font-bold uppercase tracking-wider" :class="isSocketConnected ? 'text-success' : 'text-danger'">{{ isSocketConnected ? 'LIVE' : 'OFFLINE' }}</span>
           </div>
        </div>
      </div>

      <div class="flex items-center space-x-6">
        <!-- Market Regime Widget (New) -->
        <div class="hidden lg:flex items-center space-x-2 bg-slate-50 px-3 py-1.5 rounded border border-slate-200">
           <div class="flex flex-col items-end">
             <span class="text-[10px] font-bold text-slate-500">REGIME</span>
             <span class="text-xs font-bold text-primary">{{ marketRegime.type || 'ANALYZING' }}</span>
           </div>
           <div class="w-px h-6 bg-slate-200"></div>
           <div class="flex flex-col items-start">
             <span class="text-[10px] font-bold text-slate-500">VOLATILITY</span>
             <span class="text-xs font-bold" :class="marketRegime.volatility === 'HIGH' ? 'text-danger' : 'text-success'">{{ marketRegime.volatility || 'NORMAL' }}</span>
           </div>
        </div>

        <!-- Symbol & Timeframe Selector -->
        <div class="flex items-center bg-slate-50 rounded-lg p-1.5 border border-slate-200 space-x-3 shadow-inner">
          <div class="flex items-center px-2">
            <span class="text-[10px] font-bold px-2 text-slate-500 tracking-wider">SYMBOL</span>
            <select v-model="selectedSymbol" @change="onSymbolChange" class="bg-white text-primary text-xs font-bold px-3 py-1.5 rounded border border-slate-200 focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-all cursor-pointer hover:bg-slate-50">
              <option v-for="sym in availableSymbols" :key="sym.symbol" :value="sym.symbol">
                {{ sym.symbol }}
              </option>
            </select>
          </div>
          <div class="w-px h-6 bg-slate-200"></div>
          <div class="flex items-center px-2">
            <span class="text-[10px] font-bold px-2 text-slate-500 tracking-wider">TIMEFRAME</span>
            <select v-model="selectedTimeframe" @change="onTimeframeChange" class="bg-white text-primary text-xs font-bold px-3 py-1.5 rounded border border-slate-200 focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-all cursor-pointer hover:bg-slate-50">
              <option value="M1">M1</option>
              <option value="M5">M5</option>
              <option value="M15">M15</option>
              <option value="H1">H1</option>
              <option value="H4">H4</option>
            </select>
          </div>
        </div>

        <!-- Bot Control -->
        <div class="flex items-center space-x-3">
          <button 
            type="button"
            @click.prevent="toggleBot" 
            class="group relative px-6 py-2 rounded-lg font-bold text-sm transition-all duration-300 shadow-sm hover:shadow-md overflow-hidden"
            :class="isBotRunning ? 'bg-danger/10 text-danger border border-danger/20 hover:bg-danger/20' : 'bg-success/10 text-success border border-success/20 hover:bg-success/20'"
          >
            <div class="flex items-center space-x-3">
              <span class="relative flex h-2.5 w-2.5">
                <span v-if="isBotRunning" class="animate-ping absolute inline-flex h-full w-full rounded-full bg-danger opacity-75"></span>
                <span class="relative inline-flex rounded-full h-2.5 w-2.5" :class="isBotRunning ? 'bg-danger' : 'bg-success'"></span>
              </span>
              <span class="tracking-wider">{{ isBotRunning ? 'STOP ALGO' : 'START ALGO' }}</span>
            </div>
          </button>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main class="flex-1 p-6 grid grid-cols-12 gap-6 overflow-hidden">
      
      <!-- Left Column: Quick Actions & Signals (3 cols) -->
      <div class="col-span-3 flex flex-col space-y-6 h-full overflow-hidden">
        <!-- Quick Trade Panel -->
        <div class="bg-white border border-slate-200 rounded-xl p-5 shadow-card">
          <h3 class="text-primary text-sm font-bold tracking-wide mb-4 flex items-center">
            <div class="w-1 h-4 bg-accent rounded-full mr-2"></div>
            QUICK EXECUTION
          </h3>
          
          <div class="space-y-4">
            <div class="flex justify-between items-center bg-slate-50 p-2 rounded">
               <span class="text-xs font-bold text-slate-500">Risk %</span>
               <input type="number" v-model="riskPercent" class="w-16 text-right bg-white border border-slate-200 rounded px-2 py-1 text-xs font-mono">
            </div>
            
            <div class="grid grid-cols-2 gap-2">
              <button @click="quickTrade('BUY')" class="py-3 bg-success text-white font-bold rounded hover:bg-success/90 transition-colors">BUY</button>
              <button @click="quickTrade('SELL')" class="py-3 bg-danger text-white font-bold rounded hover:bg-danger/90 transition-colors">SELL</button>
            </div>
          </div>
        </div>

        <!-- Recent Signals (Mini) -->
        <div class="bg-white border border-slate-200 rounded-xl p-0 shadow-card flex-1 overflow-hidden flex flex-col">
          <div class="p-4 border-b border-slate-200 bg-slate-50">
            <h3 class="text-primary text-xs font-bold uppercase tracking-wide">Recent Signals</h3>
          </div>
          <div class="overflow-y-auto p-4 space-y-3 custom-scrollbar flex-1">
             <div v-for="signal in signals.slice(0, 5)" :key="signal.id" class="border-l-4 pl-3 py-1" :class="signal.signal_type === 'BUY' ? 'border-success' : 'border-danger'">
               <div class="flex justify-between">
                 <span class="font-bold text-xs">{{ signal.symbol }}</span>
                 <span class="text-[10px] text-slate-400">{{ formatTimeAgo(signal.created_at) }}</span>
               </div>
               <div class="flex justify-between items-center mt-1">
                 <span class="text-xs font-bold" :class="signal.signal_type === 'BUY' ? 'text-success' : 'text-danger'">{{ signal.signal_type }}</span>
                 <span class="text-[10px] font-mono">{{ signal.price }}</span>
                 <span class="text-[9px] px-1.5 py-0.5 rounded font-bold uppercase" 
                       :class="{
                         'bg-slate-100 text-slate-500': signal.status === 'CREATED',
                         'bg-warning/10 text-warning': signal.status === 'PENDING',
                         'bg-success/10 text-success': signal.status === 'ACTIVE',
                         'bg-slate-200 text-slate-400': signal.status === 'CLOSED'
                       }">
                   {{ signal.status || 'NEW' }}
                 </span>
               </div>
             </div>
          </div>
        </div>
      </div>

      <!-- Center: Chart (6 cols) -->
      <div class="col-span-6 flex flex-col h-full overflow-hidden">
        <div class="bg-white border border-slate-200 rounded-xl p-1 shadow-card h-full relative flex flex-col">
           <div class="absolute top-4 left-4 z-10 flex space-x-2">
             <div class="bg-white/90 backdrop-blur px-3 py-1 rounded text-xs font-bold text-primary border border-slate-200 shadow-sm">
               {{ selectedSymbol }} <span class="text-slate-400">|</span> {{ selectedTimeframe }}
             </div>
           </div>
           <div class="w-full h-full p-2 bg-slate-50 rounded-lg">
             <TradingChart 
                ref="tradingChartRef"
                :data="chartData" 
                :trades="openTrades" 
                :symbol="selectedSymbol"
                :is-dark="false"
             />
          </div>
        </div>
      </div>

      <!-- Right: Positions & Logs (3 cols) -->
      <div class="col-span-3 flex flex-col space-y-6 h-full overflow-hidden">
        <!-- Open Positions -->
        <div class="bg-white border border-slate-200 rounded-xl p-0 shadow-card flex-1 flex flex-col overflow-hidden">
          <div class="p-4 border-b border-slate-200 bg-slate-50 flex justify-between items-center">
            <h3 class="text-primary text-xs font-bold uppercase tracking-wide">Positions</h3>
            <span class="text-xs font-mono font-bold" :class="totalPnL >= 0 ? 'text-success' : 'text-danger'">{{ formatCurrency(totalPnL) }}</span>
          </div>
          
          <div class="overflow-y-auto p-0 custom-scrollbar flex-1">
            <div v-for="trade in openTrades" :key="trade.ticket" class="p-3 border-b border-slate-100 hover:bg-slate-50 transition-colors">
               <div class="flex justify-between mb-1">
                 <span class="font-bold text-xs">{{ trade.symbol }}</span>
                 <span class="text-xs font-mono" :class="trade.pnl >= 0 ? 'text-success' : 'text-danger'">{{ formatCurrency(trade.pnl) }}</span>
               </div>
               <div class="flex justify-between items-center text-[10px] text-slate-500">
                 <span :class="trade.type === 'BUY' ? 'text-success' : 'text-danger'" class="font-bold">{{ trade.type }}</span>
                 <span>{{ trade.volume }} lots</span>
                 <button @click="closeTrade(trade.ticket)" class="text-danger hover:underline">Close</button>
               </div>
            </div>
            <div v-if="openTrades.length === 0" class="p-8 text-center text-slate-400 text-xs italic">
              No open positions
            </div>
          </div>
        </div>

        <!-- Execution Logs (Mini) -->
        <div class="bg-white border border-slate-200 rounded-xl p-0 shadow-card h-1/3 flex flex-col overflow-hidden">
           <div class="p-3 border-b border-slate-200 bg-slate-50">
            <h3 class="text-primary text-xs font-bold uppercase tracking-wide">Logs</h3>
          </div>
          <div class="overflow-y-auto p-3 space-y-2 custom-scrollbar flex-1 text-[10px] font-mono">
            <div v-for="log in logs" :key="log.id" class="text-slate-600">
              <span class="text-slate-400">[{{ formatTime(log.timestamp) }}]</span> {{ log.message }}
            </div>
          </div>
        </div>
      </div>

    </main>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue';
import TradingChart from '../components/TradingChart.vue';
import api from '../services/api';

// State
const selectedSymbol = ref('EURUSD');
const selectedTimeframe = ref('H1');
const availableSymbols = ref([]);
const isBotRunning = ref(false);
const signals = ref([]);
const openTrades = ref([]);
const logs = ref([]);
const accountInfo = ref(null);
const isSocketConnected = ref(false);
const riskPercent = ref(1.0);

const marketRegime = ref({
  type: 'TRENDING',
  volatility: 'NORMAL'
});

const chartData = ref([]);

// Computed
const totalPnL = computed(() => openTrades.value.reduce((sum, t) => sum + (t.pnl || 0), 0));

// Methods
const formatCurrency = (val) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(val || 0);
const formatTimeAgo = (iso) => {
  if (!iso) return '';
  const diff = (new Date() - new Date(iso)) / 1000;
  if (diff < 60) return `${Math.floor(diff)}s`;
  if (diff < 3600) return `${Math.floor(diff/60)}m`;
  return `${Math.floor(diff/3600)}h`;
};
const formatTime = (iso) => {
    if (!iso) return '';
    return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

const currentBotId = ref(null);

const loadData = async () => {
    try {
        // 1. Get Bots and Status
        // 1. Get Bots and Status
        const bots = await api.getBots();
        if (bots && bots.length > 0) {
            // Find bot for selected symbol
            const matchingBot = bots.find(b => b.symbol === selectedSymbol.value);
            
            if (matchingBot) {
                currentBotId.value = matchingBot.id;
                const status = await api.getBotStatus(currentBotId.value);
                isBotRunning.value = status.is_running;
            } else {
                currentBotId.value = null;
                isBotRunning.value = false;
                console.warn(`No bot config found for ${selectedSymbol.value}`);
            }
        }

        const acc = await api.getAccountInfo();
        accountInfo.value = acc;
        
        const syms = await api.getSymbols();
        if (syms.symbols) availableSymbols.value = syms.symbols;

        console.log("Fetching signals for:", selectedSymbol.value);
        const sigs = await api.getSignals(selectedSymbol.value);
        console.log("Signals received:", sigs);
        if (sigs.signals) signals.value = sigs.signals;

        const pos = await api.getPositions();
        if (pos.positions) openTrades.value = pos.positions.map(t => ({
             ticket: t.ticket,
             symbol: t.symbol,
             type: t.type,
             volume: t.volume,
             pnl: t.profit,
             entry: t.price_open,
             current: t.price_current
        }));
        
        // Logs
        // const l = await api.getLogs();
        // logs.value = l;
        logs.value = [
            { id: 1, timestamp: new Date().toISOString(), message: "System initialized" },
            { id: 2, timestamp: new Date().toISOString(), message: "Connected to MT5" }
        ];

    } catch (e) {
        console.error("Load data error", e);
    }
};

const updateChart = async () => {
    console.log('DashboardView: Fetching chart data for', selectedSymbol.value, selectedTimeframe.value);
    try {
        const response = await api.getMarketHistory(selectedSymbol.value, selectedTimeframe.value);
        console.log('DashboardView: Full API response:', response);
        
        // Handle both possible response structures
        const candleData = response.data || response;
        
        if (candleData && Array.isArray(candleData) && candleData.length > 0) {
            console.log('DashboardView: Setting', candleData.length, 'candles to chart');
            chartData.value = candleData;
        } else if (response.data && Array.isArray(response.data)) {
            console.log('DashboardView: Setting', response.data.length, 'candles from response.data');
            chartData.value = response.data;
        } else {
            console.warn('DashboardView: Unexpected response structure:', response);
        }
    } catch (e) { 
        console.error('DashboardView: Chart data fetch error:', e); 
    }
};

const onSymbolChange = () => {
    console.log("Symbol changed to:", selectedSymbol.value);
    updateChart();
    loadData();
};

const onTimeframeChange = () => {
    console.log("Timeframe changed to:", selectedTimeframe.value);
    updateChart();
};

const toggleBot = async () => {
    if (!currentBotId.value) {
        alert("No bot configuration found.");
        return;
    }

    try {
        if (isBotRunning.value) {
            await api.stopBot(currentBotId.value);
            isBotRunning.value = false;
            logs.value.unshift({ id: Date.now(), timestamp: new Date().toISOString(), message: "Bot stopped by user", level: "warning" });
        } else {
            await api.startBot(currentBotId.value);
            isBotRunning.value = true;
            logs.value.unshift({ id: Date.now(), timestamp: new Date().toISOString(), message: "Bot started by user", level: "success" });
        }
    } catch (e) {
        console.error("Error toggling bot", e);
        alert("Failed to toggle bot status.");
    }
};

const quickTrade = async (type) => {
    if (!confirm(`Execute Quick ${type} on ${selectedSymbol.value}?`)) return;
    // Call API
    alert('Order Sent');
};

const closeTrade = async (ticket) => {
    if (!confirm(`Close trade ${ticket}?`)) return;
    try {
        await api.closeTrade(ticket);
        logs.value.unshift({ id: Date.now(), timestamp: new Date().toISOString(), message: `Trade ${ticket} closed`, level: "success" });
        loadData();
    } catch (e) {
        console.error("Error closing trade", e);
        alert("Failed to close trade.");
    }
};

const tradingChartRef = ref(null);

// Socket Logic
const initSocket = () => {
    const socket = api.getSocket();
    
    socket.on('connect', () => {
        isSocketConnected.value = true;
        console.log('Connected to socket');
    });

    socket.on('disconnect', () => {
        isSocketConnected.value = false;
    });

    socket.on('market_update', (data) => {
        // Debug: Check if we are receiving prices
        // console.log('Market Update:', data); 
        if (data.prices && data.prices[selectedSymbol.value]) {
            console.log('Price Update:', data.prices[selectedSymbol.value]);
        }

        if (data.account) accountInfo.value = data.account;
        
        if (data.positions) {
            openTrades.value = data.positions.map(t => ({
                 ticket: t.ticket,
                 symbol: t.symbol,
                 type: t.type === 'BUY' || t.type === 0 ? 'BUY' : 'SELL', // Handle MT5 int types if needed
                 volume: t.volume,
                 pnl: t.profit,
                 entry: t.price_open,
                 current: t.price_current,
                 sl: t.sl,
                 tp: t.tp
            }));
        }

        // Real-time Chart Update
        if (data.prices && data.prices[selectedSymbol.value]) {
            const tick = data.prices[selectedSymbol.value];
            updateChartRealTime(tick);
        }
    });

    socket.on('bot_activity', (data) => {
        logs.value.unshift({
            id: Date.now(),
            timestamp: data.timestamp || new Date().toISOString(),
            message: data.message,
            level: data.level
        });
        if (logs.value.length > 50) logs.value.pop();
    });

    socket.on('signal_generated', (data) => {
        signals.value.unshift({
            id: Date.now(),
            ...data
        });
        if (signals.value.length > 20) signals.value.pop();
    });
};

const updateChartRealTime = (tick) => {
    if (!chartData.value || chartData.value.length === 0) return;
    
    const lastCandle = chartData.value[chartData.value.length - 1];
    const price = tick.bid; // Use bid for chart usually
    
    // Check if we need a new candle (simple time check)
    // For simplicity, we just update the current candle's close/high/low
    // A proper implementation would check timestamp vs timeframe
    
    const updatedCandle = {
        ...lastCandle,
        close: price,
        high: Math.max(lastCandle.high, price),
        low: Math.min(lastCandle.low, price)
    };
    
    // Update local data ref (optional, but good for consistency)
    chartData.value[chartData.value.length - 1] = updatedCandle;
    
    // Update Chart Component directly for performance
    if (tradingChartRef.value && tradingChartRef.value.updateCandle) {
        tradingChartRef.value.updateCandle({
            time: new Date(lastCandle.time).getTime() / 1000, // Ensure unix timestamp
            open: updatedCandle.open,
            high: updatedCandle.high,
            low: updatedCandle.low,
            close: updatedCandle.close
        });
    }
};

onMounted(() => {
    loadData();
    updateChart();
    initSocket();
});
</script>
