<template>
  <div class="relative overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-r from-slate-900/90 via-slate-800/90 to-slate-900/90 backdrop-blur-xl p-6 shadow-2xl">
    <!-- Animated gradient orbs in background -->
    <div class="absolute -top-20 -left-20 w-40 h-40 bg-blue-500/20 rounded-full blur-3xl animate-pulse"></div>
    <div class="absolute -bottom-20 -right-20 w-40 h-40 bg-purple-500/20 rounded-full blur-3xl animate-pulse" style="animation-delay: 1s"></div>
    
    <!-- Top Row: Mode Toggle + Account Selector -->
    <div class="relative z-10 flex justify-between items-center mb-6">
      <!-- Modern Mode Toggle -->
      <div class="flex items-center space-x-1 p-1 bg-gray-800/60 rounded-xl border border-gray-700/50">
        <button 
          @click="$emit('update:modelValue', 'backtest')"
          class="relative px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-300"
          :class="modelValue === 'backtest' 
            ? 'bg-gradient-to-r from-blue-600 to-cyan-500 text-white shadow-lg shadow-blue-500/30' 
            : 'text-gray-400 hover:text-white hover:bg-gray-700/50'"
        >
          <span class="flex items-center gap-2">
            📊 <span>Backtest</span>
          </span>
        </button>
        <button 
          @click="$emit('update:modelValue', 'live')"
          class="relative px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-300"
          :class="modelValue === 'live' 
            ? 'bg-gradient-to-r from-red-600 to-orange-500 text-white shadow-lg shadow-red-500/30' 
            : 'text-gray-400 hover:text-white hover:bg-gray-700/50'"
        >
          <span class="flex items-center gap-2">
            <span v-if="modelValue === 'live'" class="relative flex h-2 w-2">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-red-500"></span>
            </span>
            <span v-else>🔴</span>
            <span>Live</span>
          </span>
        </button>
        <button 
          @click="$emit('update:modelValue', 'paper')"
          class="relative px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-300"
          :class="modelValue === 'paper' 
            ? 'bg-gradient-to-r from-purple-600 to-pink-500 text-white shadow-lg shadow-purple-500/30' 
            : 'text-gray-400 hover:text-white hover:bg-gray-700/50'"
        >
          <span class="flex items-center gap-2">
            📋 <span>Paper</span>
          </span>
        </button>
      </div>

      <!-- GLOBAL KILL SWITCH (Admin) -->
      <div class="flex items-center space-x-2 mr-4">
        <button 
          @click="$emit('toggle-kill-switch')"
          class="relative px-4 py-2 rounded-lg font-bold text-xs uppercase tracking-wider transition-all duration-300 border shadow-lg"
          :class="killSwitchActive 
            ? 'bg-red-600 border-red-500 text-white animate-pulse hover:bg-red-700' 
            : 'bg-emerald-900/30 border-emerald-500/30 text-emerald-400 hover:bg-emerald-800/50 hover:text-emerald-300'"
        >
          <span class="flex items-center gap-2">
            <span v-if="killSwitchActive">💀 KILL SWITCH ACTIVE</span>
            <span v-else>🛡️ SYSTEM SECURE</span>
          </span>
        </button>
      </div>
      
      <!-- Connection Status Badge -->
      <div class="flex items-center px-3 py-1.5 rounded-lg bg-gray-800/40 border border-gray-700/30">
        <div v-if="socketConnected" class="flex items-center gap-2">
          <span class="relative flex h-2.5 w-2.5">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
            <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-green-500"></span>
          </span>
          <span class="text-xs text-green-400 font-medium">Connected</span>
        </div>
        <div v-else-if="socketReconnecting" class="flex items-center gap-2">
          <svg class="w-3 h-3 text-yellow-400 animate-spin" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          <span class="text-xs text-yellow-400 font-medium">Reconnecting...</span>
        </div>
        <div v-else class="flex items-center gap-2">
          <span class="relative flex h-2.5 w-2.5">
            <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-red-500"></span>
          </span>
          <span class="text-xs text-red-400 font-medium">Disconnected</span>
        </div>
      </div>
      
      <!-- Account Selector -->
      <div class="flex items-center space-x-3">
        <select 
          :value="selectedAccountId"
          @change="$emit('update:selectedAccountId', $event.target.value); $emit('account-change')"
          class="px-4 py-2.5 bg-gray-800/60 border border-gray-600/50 rounded-xl text-sm text-white focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20 backdrop-blur transition-all"
          :disabled="modelValue === 'backtest'"
        >
          <option :value="null">Select Account</option>
          <option v-for="acc in accounts" :key="acc.id" :value="acc.id">
            {{ acc.name }} ({{ acc.account_type }})
          </option>
        </select>
        <router-link 
          to="/accounts"
          class="px-4 py-2.5 bg-gray-700/50 hover:bg-gray-600/50 text-white text-sm rounded-xl transition-all border border-gray-600/30 hover:border-gray-500/50"
        >
          ⚙️ Accounts
        </router-link>
      </div>
    </div>
    
    <!-- KPI Cards Row -->
    <div class="relative z-10 grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4">
      <!-- Balance KPI -->
      <div class="group relative overflow-hidden rounded-xl bg-gradient-to-br from-emerald-500/10 to-green-600/5 border border-emerald-500/20 p-4 hover:border-emerald-400/40 transition-all hover:scale-[1.02]">
        <div class="absolute inset-0 bg-gradient-to-t from-emerald-500/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity"></div>
        <div class="text-xs text-emerald-400/70 font-medium mb-1">💰 Balance</div>
        <div class="text-xl font-bold text-emerald-400">${{ modelValue === 'live' ? (activeAccount?.starting_balance || 10000).toLocaleString() : sharedConfig.initial_balance.toLocaleString() }}</div>
        <div v-if="portfolioMetrics.netProfit !== 0" class="text-xs mt-1" :class="portfolioMetrics.netProfit >= 0 ? 'text-emerald-300' : 'text-red-400'">
          {{ portfolioMetrics.netProfit >= 0 ? '↑' : '↓' }} {{ Math.abs(portfolioMetrics.netProfit).toFixed(0) }} ({{ ((portfolioMetrics.netProfit / sharedConfig.initial_balance) * 100).toFixed(1) }}%)
        </div>
      </div>
      
      <!-- Drawdown KPI -->
      <div class="group relative overflow-hidden rounded-xl border p-4 transition-all hover:scale-[1.02]"
           :class="riskStatus.total_dd_percent > 5 
             ? 'bg-gradient-to-br from-red-500/10 to-red-600/5 border-red-500/30' 
             : 'bg-gradient-to-br from-blue-500/10 to-cyan-600/5 border-blue-500/20 hover:border-blue-400/40'">
        <div class="text-xs font-medium mb-1" :class="riskStatus.total_dd_percent > 5 ? 'text-red-400/70' : 'text-blue-400/70'">📉 Max DD</div>
        <div class="text-xl font-bold" :class="riskStatus.total_dd_percent > 5 ? 'text-red-400' : 'text-blue-400'">
          {{ modelValue === 'live' ? riskStatus.total_dd_percent?.toFixed(1) || '0.0' : portfolioMetrics.maxDrawdown?.toFixed(1) || '0.0' }}%
        </div>
        <div class="w-full bg-gray-700/50 rounded-full h-1.5 mt-2">
          <div class="h-1.5 rounded-full transition-all duration-500"
               :class="riskStatus.total_dd_percent > 5 ? 'bg-red-500' : 'bg-blue-500'"
               :style="{ width: Math.min((modelValue === 'live' ? riskStatus.total_dd_percent : portfolioMetrics.maxDrawdown) / 10 * 100, 100) + '%' }"></div>
        </div>
      </div>
      
      <!-- Win Rate KPI -->
      <div class="group relative overflow-hidden rounded-xl border p-4 transition-all hover:scale-[1.02]"
           :class="portfolioMetrics.winRate >= 50 
             ? 'bg-gradient-to-br from-green-500/10 to-emerald-600/5 border-green-500/20 hover:border-green-400/40' 
             : 'bg-gradient-to-br from-yellow-500/10 to-amber-600/5 border-yellow-500/20'">
        <div class="text-xs font-medium mb-1" :class="portfolioMetrics.winRate >= 50 ? 'text-green-400/70' : 'text-yellow-400/70'">🎯 Win Rate</div>
        <div class="text-xl font-bold" :class="portfolioMetrics.winRate >= 50 ? 'text-green-400' : 'text-yellow-400'">
          {{ portfolioMetrics.winRate?.toFixed(1) || '0.0' }}%
        </div>
        <div class="text-xs mt-1 text-gray-400">{{ portfolioMetrics.totalTrades || 0 }} trades</div>
      </div>
      
      <!-- Profit Factor KPI -->
      <div class="group relative overflow-hidden rounded-xl border p-4 transition-all hover:scale-[1.02]"
           :class="portfolioMetrics.profitFactor >= 1.5 
             ? 'bg-gradient-to-br from-violet-500/10 to-purple-600/5 border-violet-500/20 hover:border-violet-400/40' 
             : 'bg-gradient-to-br from-orange-500/10 to-amber-600/5 border-orange-500/20'">
        <div class="text-xs font-medium mb-1" :class="portfolioMetrics.profitFactor >= 1.5 ? 'text-violet-400/70' : 'text-orange-400/70'">⚖️ Profit Factor</div>
        <div class="text-xl font-bold" :class="portfolioMetrics.profitFactor >= 1.5 ? 'text-violet-400' : 'text-orange-400'">
          {{ portfolioMetrics.profitFactor?.toFixed(2) || '0.00' }}
        </div>
      </div>
      
      <!-- Active Slots -->
      <div class="group relative overflow-hidden rounded-xl bg-gradient-to-br from-cyan-500/10 to-blue-600/5 border border-cyan-500/20 p-4 hover:border-cyan-400/40 transition-all hover:scale-[1.02]">
        <div class="text-xs text-cyan-400/70 font-medium mb-1">🎰 Active Slots</div>
        <div class="text-xl font-bold text-cyan-400">{{ slots.filter(s => s.enabled).length }}</div>
        <div class="text-xs mt-1 text-gray-400">of {{ slots.length }} total</div>
      </div>
      
      <!-- Risk Exposure -->
      <div class="group relative overflow-hidden rounded-xl border p-4 transition-all hover:scale-[1.02]"
           :class="totalPotentialRisk > portfolioSynergy.max_risk 
             ? 'bg-gradient-to-br from-red-500/10 to-rose-600/5 border-red-500/30' 
             : 'bg-gradient-to-br from-teal-500/10 to-emerald-600/5 border-teal-500/20'">
        <div class="text-xs font-medium mb-1" :class="totalPotentialRisk > portfolioSynergy.max_risk ? 'text-red-400/70' : 'text-teal-400/70'">⚡ Risk Exposure</div>
        <div class="text-xl font-bold" :class="totalPotentialRisk > portfolioSynergy.max_risk ? 'text-red-400' : 'text-teal-400'">
          {{ totalPotentialRisk.toFixed(1) }}%
        </div>
        <div class="w-full bg-gray-700/50 rounded-full h-1.5 mt-2">
          <div class="h-1.5 rounded-full transition-all duration-500"
               :class="totalPotentialRisk > portfolioSynergy.max_risk ? 'bg-red-500' : totalPotentialRisk > portfolioSynergy.max_risk * 0.7 ? 'bg-yellow-500' : 'bg-teal-500'"
               :style="{ width: Math.min(totalPotentialRisk / portfolioSynergy.max_risk * 100, 100) + '%' }"></div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
defineProps({
  modelValue: { // tradingMode
    type: String,
    required: true
  },
  accounts: {
    type: Array,
    default: () => []
  },
  selectedAccountId: {
    type: [Number, String],
    default: null
  },
  killSwitchActive: {
    type: Boolean,
    default: false
  },
  socketConnected: {
    type: Boolean,
    default: false
  },
  socketReconnecting: {
    type: Boolean,
    default: false
  },
  portfolioMetrics: {
    type: Object,
    default: () => ({})
  },
  riskStatus: {
    type: Object,
    default: () => ({})
  },
  activeAccount: {
    type: Object,
    default: null
  },
  sharedConfig: {
    type: Object,
    required: true
  },
  slots: {
    type: Array,
    default: () => []
  },
  portfolioSynergy: {
    type: Object,
    default: () => ({})
  },
  totalPotentialRisk: {
    type: Number,
    default: 0
  }
})

defineEmits(['update:modelValue', 'update:selectedAccountId', 'toggle-kill-switch', 'account-change'])
</script>
