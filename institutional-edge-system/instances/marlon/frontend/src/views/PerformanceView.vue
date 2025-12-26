<template>
  <div class="min-h-screen bg-[#0f172a] text-slate-300 font-sans flex flex-col selection:bg-blue-500/30">
    <!-- Header -->
    <header class="bg-[#1e293b]/80 backdrop-blur-md border-b border-slate-700/50 p-4 flex justify-between items-center sticky top-0 z-50 shadow-2xl">
      <div class="flex items-center space-x-6">
        <div class="flex flex-col">
          <div class="text-2xl font-black tracking-tighter text-transparent bg-clip-text bg-gradient-to-r from-purple-400 via-pink-400 to-rose-400 filter drop-shadow-lg">
            PERFORMANCE ANALYTICS
          </div>
          <div class="text-[10px] font-mono text-slate-500 tracking-[0.2em] uppercase">
            Institutional Edge Pro
          </div>
        </div>
      </div>

      <div class="flex items-center space-x-4">
        <select v-model="selectedPeriod" @change="fetchMetrics" class="bg-slate-800 text-white text-xs font-bold px-3 py-1.5 rounded border border-slate-600 focus:outline-none focus:border-purple-500 focus:ring-1 focus:ring-purple-500 transition-all cursor-pointer hover:bg-slate-700">
          <option :value="7">Last 7 Days</option>
          <option :value="30">Last 30 Days</option>
          <option :value="90">Last 90 Days</option>
          <option :value="365">Last Year</option>
        </select>
        
        <router-link to="/" class="bg-slate-800 hover:bg-slate-700 text-white px-4 py-2 rounded-lg text-xs font-bold transition-colors border border-slate-600">
          BACK TO TERMINAL
        </router-link>
      </div>
    </header>

    <main class="flex-1 p-6 space-y-6 overflow-y-auto custom-scrollbar">
      
      <!-- KPI Cards -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-6">
        <!-- Net Profit -->
        <div class="bg-[#1e293b]/50 border border-slate-700/50 rounded-xl p-5 shadow-xl backdrop-blur-sm relative overflow-hidden group">
          <div class="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity">
            <svg class="w-16 h-16 text-emerald-400" fill="currentColor" viewBox="0 0 20 20"><path d="M2 10a8 8 0 018-8v8h8a8 8 0 11-16 0z"></path><path d="M12 2.252A8.014 8.014 0 0117.748 8H12V2.252z"></path></svg>
          </div>
          <div class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1">Net Profit</div>
          <div class="text-3xl font-black tracking-tight" :class="metrics.net_profit >= 0 ? 'text-emerald-400' : 'text-red-400'">
            {{ formatCurrency(metrics.net_profit) }}
          </div>
          <div class="text-xs text-slate-500 mt-2 font-mono">
            Factor: <span class="text-white font-bold">{{ metrics.profit_factor }}</span>
          </div>
        </div>

        <!-- Win Rate -->
        <div class="bg-[#1e293b]/50 border border-slate-700/50 rounded-xl p-5 shadow-xl backdrop-blur-sm relative overflow-hidden group">
          <div class="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity">
            <svg class="w-16 h-16 text-blue-400" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z" clip-rule="evenodd"></path></svg>
          </div>
          <div class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1">Win Rate</div>
          <div class="text-3xl font-black tracking-tight text-blue-400">
            {{ metrics.win_rate }}%
          </div>
          <div class="text-xs text-slate-500 mt-2 font-mono">
            <span class="text-emerald-400 font-bold">{{ metrics.winning_trades }}</span> W / <span class="text-red-400 font-bold">{{ metrics.losing_trades }}</span> L
          </div>
        </div>

        <!-- Total Trades -->
        <div class="bg-[#1e293b]/50 border border-slate-700/50 rounded-xl p-5 shadow-xl backdrop-blur-sm relative overflow-hidden group">
          <div class="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity">
            <svg class="w-16 h-16 text-purple-400" fill="currentColor" viewBox="0 0 20 20"><path d="M7 3a1 1 0 000 2h6a1 1 0 100-2H7zM4 7a1 1 0 011-1h10a1 1 0 110 2H5a1 1 0 01-1-1zM2 11a2 2 0 012-2h12a2 2 0 012 2v4a2 2 0 01-2 2H4a2 2 0 01-2-2v-4z"></path></svg>
          </div>
          <div class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1">Total Trades</div>
          <div class="text-3xl font-black tracking-tight text-purple-400">
            {{ metrics.total_trades }}
          </div>
          <div class="text-xs text-slate-500 mt-2 font-mono">
            Avg Win: {{ formatCurrency(metrics.largest_win) }}
          </div>
        </div>
        
        <!-- Largest Win -->
        <div class="bg-[#1e293b]/50 border border-slate-700/50 rounded-xl p-5 shadow-xl backdrop-blur-sm relative overflow-hidden group">
          <div class="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity">
            <svg class="w-16 h-16 text-yellow-400" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M5 2a1 1 0 011 1v1h1a1 1 0 010 2H6v1a1 1 0 01-2 0V6H3a1 1 0 010-2h1V3a1 1 0 011-1zm0 5a1 1 0 011 1v1h1a1 1 0 110 2H6v1a1 1 0 11-2 0v-1H3a1 1 0 110-2h1V8a1 1 0 011-1zm5-5a1 1 0 011 1v1h1a1 1 0 110 2h-1v1a1 1 0 11-2 0v-1H9a1 1 0 110-2h1V3a1 1 0 011-1z" clip-rule="evenodd"></path></svg>
          </div>
          <div class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1">Best Trade</div>
          <div class="text-3xl font-black tracking-tight text-yellow-400">
            {{ formatCurrency(metrics.largest_win) }}
          </div>
          <div class="text-xs text-slate-500 mt-2 font-mono">
            Worst: <span class="text-red-400">{{ formatCurrency(metrics.largest_loss) }}</span>
          </div>
        </div>
      </div>

      <!-- Trade History -->
      <div class="bg-[#1e293b]/50 border border-slate-700/50 rounded-xl p-6 shadow-xl backdrop-blur-sm">
        <div class="flex justify-between items-center mb-6">
           <div class="flex items-center space-x-2">
             <div class="w-1 h-4 bg-purple-500 rounded-full"></div>
             <h3 class="text-white text-sm font-bold tracking-wide">TRADE HISTORY</h3>
           </div>
        </div>
        
        <div class="overflow-x-auto">
          <table class="w-full text-sm text-left border-collapse">
            <thead class="text-[10px] text-slate-500 uppercase bg-slate-900/50">
              <tr>
                <th class="px-4 py-3 font-bold tracking-wider rounded-tl-lg">Date</th>
                <th class="px-4 py-3 font-bold tracking-wider">Symbol</th>
                <th class="px-4 py-3 font-bold tracking-wider">Type</th>
                <th class="px-4 py-3 font-bold tracking-wider">Entry</th>
                <th class="px-4 py-3 font-bold tracking-wider">Exit</th>
                <th class="px-4 py-3 font-bold tracking-wider">PnL</th>
                <th class="px-4 py-3 font-bold tracking-wider rounded-tr-lg">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-800">
              <tr v-for="trade in history" :key="trade.id" class="hover:bg-slate-700/30 transition-colors">
                <td class="px-4 py-3 font-mono text-slate-400 text-xs">{{ formatDate(trade.closed_at) }}</td>
                <td class="px-4 py-3 font-bold text-white">{{ trade.symbol }}</td>
                <td class="px-4 py-3 text-xs font-bold" :class="trade.trade_type === 'BUY' ? 'text-emerald-400' : 'text-red-400'">{{ trade.trade_type }}</td>
                <td class="px-4 py-3 font-mono text-slate-400 text-xs">{{ trade.entry_price }}</td>
                <td class="px-4 py-3 font-mono text-slate-400 text-xs">{{ trade.exit_price || '-' }}</td>
                <td class="px-4 py-3 font-mono font-bold text-xs" :class="trade.profit_loss >= 0 ? 'text-emerald-400' : 'text-red-400'">
                  {{ formatCurrency(trade.profit_loss) }}
                </td>
                <td class="px-4 py-3">
                  <span class="px-2 py-0.5 rounded text-[10px] font-bold bg-slate-800 text-slate-400 border border-slate-700">{{ trade.status }}</span>
                </td>
              </tr>
              <tr v-if="history.length === 0">
                <td colspan="7" class="px-4 py-12 text-center text-slate-500 italic text-xs">No trade history available</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import api from '../services/api';

const selectedPeriod = ref(30);
const metrics = ref({
  total_trades: 0,
  winning_trades: 0,
  losing_trades: 0,
  win_rate: 0,
  net_profit: 0,
  profit_factor: 0,
  largest_win: 0,
  largest_loss: 0
});
const history = ref([]);

const fetchMetrics = async () => {
  try {
    metrics.value = await api.getPerformanceMetrics(selectedPeriod.value);
  } catch (e) {
    console.error("Error fetching metrics:", e);
  }
};

const fetchHistory = async () => {
  try {
    history.value = await api.getTradeHistory(100);
  } catch (e) {
    console.error("Error fetching history:", e);
  }
};

const formatCurrency = (val) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(val);
const formatDate = (iso) => {
  if (!iso) return '-';
  return new Date(iso).toLocaleString();
};

onMounted(() => {
  fetchMetrics();
  fetchHistory();
});
</script>
