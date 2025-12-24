<template>
  <div class="p-6 space-y-6 min-h-screen bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900">
    
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- 🎨 MODERN KPI DASHBOARD HEADER (Glassmorphism + Gradients)              -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <div class="relative overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-r from-slate-900/90 via-slate-800/90 to-slate-900/90 backdrop-blur-xl p-6 shadow-2xl">
      <!-- Animated gradient orbs in background -->
      <div class="absolute -top-20 -left-20 w-40 h-40 bg-blue-500/20 rounded-full blur-3xl animate-pulse"></div>
      <div class="absolute -bottom-20 -right-20 w-40 h-40 bg-purple-500/20 rounded-full blur-3xl animate-pulse" style="animation-delay: 1s"></div>
      
      <!-- Top Row: Mode Toggle + Account Selector -->
      <div class="relative z-10 flex justify-between items-center mb-6">
        <!-- Modern Mode Toggle -->
        <div class="flex items-center space-x-1 p-1 bg-gray-800/60 rounded-xl border border-gray-700/50">
          <button 
            @click="tradingMode = 'backtest'"
            class="relative px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-300"
            :class="tradingMode === 'backtest' 
              ? 'bg-gradient-to-r from-blue-600 to-cyan-500 text-white shadow-lg shadow-blue-500/30' 
              : 'text-gray-400 hover:text-white hover:bg-gray-700/50'"
          >
            <span class="flex items-center gap-2">
              📊 <span>Backtest</span>
            </span>
          </button>
          <button 
            @click="tradingMode = 'live'"
            class="relative px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-300"
            :class="tradingMode === 'live' 
              ? 'bg-gradient-to-r from-red-600 to-orange-500 text-white shadow-lg shadow-red-500/30' 
              : 'text-gray-400 hover:text-white hover:bg-gray-700/50'"
          >
            <span class="flex items-center gap-2">
              <span v-if="tradingMode === 'live'" class="relative flex h-2 w-2">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"></span>
                <span class="relative inline-flex rounded-full h-2 w-2 bg-red-500"></span>
              </span>
              <span v-else>🔴</span>
              <span>Live</span>
            </span>
          </button>
          <button 
            @click="tradingMode = 'paper'"
            class="relative px-5 py-2.5 rounded-lg font-semibold text-sm transition-all duration-300"
            :class="tradingMode === 'paper' 
              ? 'bg-gradient-to-r from-purple-600 to-pink-500 text-white shadow-lg shadow-purple-500/30' 
              : 'text-gray-400 hover:text-white hover:bg-gray-700/50'"
          >
            <span class="flex items-center gap-2">
              📋 <span>Paper</span>
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
            v-model="selectedAccountId"
            @change="onAccountChange"
            class="px-4 py-2.5 bg-gray-800/60 border border-gray-600/50 rounded-xl text-sm text-white focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20 backdrop-blur transition-all"
            :disabled="tradingMode === 'backtest'"
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
          <div class="text-xl font-bold text-emerald-400">${{ tradingMode === 'live' ? (activeAccount?.starting_balance || 10000).toLocaleString() : sharedConfig.initial_balance.toLocaleString() }}</div>
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
            {{ tradingMode === 'live' ? riskStatus.total_dd_percent?.toFixed(1) || '0.0' : portfolioMetrics.maxDrawdown?.toFixed(1) || '0.0' }}%
          </div>
          <div class="w-full bg-gray-700/50 rounded-full h-1.5 mt-2">
            <div class="h-1.5 rounded-full transition-all duration-500"
                 :class="riskStatus.total_dd_percent > 5 ? 'bg-red-500' : 'bg-blue-500'"
                 :style="{ width: Math.min((tradingMode === 'live' ? riskStatus.total_dd_percent : portfolioMetrics.maxDrawdown) / 10 * 100, 100) + '%' }"></div>
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

    <!-- Header -->
    <div class="flex justify-between items-center">
      <div>
        <h1 class="text-2xl font-bold text-white">{{ tradingMode === 'backtest' ? 'Strategy Backtester' : '🔴 Live Trading' }}</h1>
        <p class="text-gray-400">{{ tradingMode === 'backtest' ? 'Test strategies with historical data before going live' : 'Trading live with real money - FundedPips rules active' }}</p>
      </div>
      <div class="flex space-x-3">
        <button 
          @click="runBacktest" 
          :disabled="isRunning || (tradingMode === 'live' && !activeAccount)"
          class="px-4 py-2 text-white rounded-lg font-medium flex items-center transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          :class="tradingMode === 'backtest' ? 'bg-blue-600 hover:bg-blue-700' : 'bg-red-600 hover:bg-red-700'"
        >
          <span v-if="isRunning && tradingMode === 'backtest'" class="mr-2 animate-spin">⟳</span>
          {{ isRunning ? (tradingMode === 'backtest' ? `Running (${progress}%)` : '🔴 Trading Active') : (tradingMode === 'backtest' ? 'Run Backtest' : 'Start Trading') }}
        </button>
         <!-- Stop Trading Button (Live mode only) -->
        <button 
          v-if="tradingMode === 'live' && isRunning"
          @click="stopLiveTrading"
          class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded-lg font-medium flex items-center transition-colors"
        >
          ⏹️ Stop All
        </button>
        <!-- Load Positions Button (Live mode only) -->
        <button 
          v-if="tradingMode === 'live'"
          @click="loadOpenPositions"
          class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded-lg font-medium flex items-center transition-colors"
        >
          🔄 Load Positions
        </button>
        <!-- Export CSV Button (Backtest mode only) -->
        <button 
          v-if="tradingMode === 'backtest'"
          @click="exportPortfolioCSV"
          :disabled="portfolioMetrics.totalTrades === 0"
          class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded-lg font-medium flex items-center transition-colors disabled:opacity-50"
        >
          📄 Export CSV
        </button>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- 🎰 PORTFOLIO SLOTS (Modern Card Grid)                                   -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <div class="relative overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-r from-slate-900/80 via-slate-800/80 to-slate-900/80 backdrop-blur-xl p-5 shadow-xl">
      <div class="flex justify-between items-center mb-4">
        <div class="flex items-center space-x-3">
          <h3 class="text-lg font-bold text-white flex items-center gap-2">
            <span class="text-2xl">🎰</span> 
            <span class="bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">Portfolio Slots</span>
          </h3>
          <button @click="addSlot" 
                  class="group px-3 py-1.5 bg-gradient-to-r from-emerald-600 to-green-500 hover:from-emerald-500 hover:to-green-400 text-white text-xs font-semibold rounded-lg transition-all shadow-lg shadow-emerald-500/20 hover:shadow-emerald-400/30 hover:scale-105">
            <span class="flex items-center gap-1">
              <span class="group-hover:rotate-90 transition-transform duration-300">➕</span>
              <span>Add Slot</span>
            </span>
          </button>
        </div>
        <div class="flex items-center space-x-3">
          <!-- Capital Input -->
          <div class="flex items-center gap-2 bg-gray-800/60 rounded-xl px-3 py-2 border border-gray-700/50">
            <span class="text-xs text-gray-400">💵 Capital</span>
            <input type="number" v-model.number="sharedConfig.initial_balance" 
                   class="bg-transparent text-sm text-white w-20 focus:outline-none text-right font-mono">
          </div>
          <div class="hidden md:flex items-center gap-3 text-xs text-gray-400">
            <span class="px-2 py-1 bg-gray-800/40 rounded-lg border border-gray-700/30">
              Max Risk: <span class="text-yellow-400 font-semibold">{{ portfolioSynergy.max_risk }}%</span>
            </span>
            <span class="px-2 py-1 bg-gray-800/40 rounded-lg border border-gray-700/30">
              Max/Symbol: <span class="text-cyan-400 font-semibold">{{ portfolioSynergy.max_positions }}</span>
            </span>
          </div>
        </div>
      </div>
      
      <!-- Slot Cards Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div v-for="slot in slots" :key="slot.id" 
             class="group relative overflow-hidden rounded-xl border transition-all duration-300 hover:scale-[1.01]"
             :class="slot.enabled 
               ? 'bg-gradient-to-br from-slate-800/80 to-slate-900/80 border-blue-500/50 shadow-lg shadow-blue-500/10' 
               : 'bg-gray-900/50 border-gray-700/50 opacity-60'">
          
          <!-- Slot glow effect when enabled -->
          <div v-if="slot.enabled" class="absolute inset-0 bg-gradient-to-br from-blue-500/5 to-purple-500/5 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none"></div>
          
          <!-- Slot Header -->
          <div class="relative z-10 p-3 flex justify-between items-center border-b border-gray-700/50">
            <label class="flex items-center space-x-2 cursor-pointer">
              <div class="relative">
                <input type="checkbox" v-model="slot.enabled" @change="saveSlot(slot)" 
                       class="sr-only peer">
                <div class="w-5 h-5 rounded bg-gray-700 border border-gray-600 peer-checked:bg-gradient-to-r peer-checked:from-blue-600 peer-checked:to-cyan-500 peer-checked:border-transparent transition-all flex items-center justify-center">
                  <svg v-if="slot.enabled" class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"></path>
                  </svg>
                </div>
              </div>
              <span class="text-sm font-bold" :class="slot.enabled ? 'text-white' : 'text-gray-400'">
                Slot {{ slot.id + 1 }}
              </span>
            </label>
            <div class="flex items-center space-x-2">
              <button @click="slot.expanded = !slot.expanded" 
                      class="p-1 rounded hover:bg-gray-700/50 text-gray-400 hover:text-white transition-colors">
                <svg class="w-4 h-4 transition-transform" :class="slot.expanded ? 'rotate-180' : ''" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                </svg>
              </button>
              <button @click="deleteSlot(slot.id)" 
                      class="p-1 rounded hover:bg-red-500/20 text-red-400 hover:text-red-300 transition-colors" 
                      title="Delete Slot">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                </svg>
              </button>
            </div>
          </div>
          
          <!-- Symbol + Direction (always visible) -->
          <div class="p-3 space-y-2">
            <select v-model="slot.symbol" :disabled="!slot.enabled" 
                    @change="applySymbolPreset(slot)"
                    class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-sm disabled:opacity-50">
              <option v-for="(preset, sym) in symbolPresets" :key="sym" :value="sym">
                {{ preset.emoji }} {{ preset.name }}
              </option>
            </select>
            <!-- Symbol Info -->
            <div v-if="symbolPresets[slot.symbol]" class="text-[10px] text-gray-500 px-1">
              {{ symbolPresets[slot.symbol].description }}
              <span class="ml-1 px-1 rounded" 
                    :class="symbolPresets[slot.symbol].volatility === 'EXTREME' ? 'bg-red-900 text-red-400' :
                            symbolPresets[slot.symbol].volatility === 'HIGH' ? 'bg-orange-900 text-orange-400' :
                            symbolPresets[slot.symbol].volatility === 'MEDIUM' ? 'bg-yellow-900 text-yellow-400' :
                            'bg-green-900 text-green-400'">
                {{ symbolPresets[slot.symbol].volatility }}
              </span>
            </div>
            <select v-model="slot.direction" :disabled="!slot.enabled"
                    class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-xs disabled:opacity-50"
                    :class="slot.direction === 'BUY_ONLY' ? 'text-green-400' : slot.direction === 'SELL_ONLY' ? 'text-red-400' : 'text-gray-300'">
              <option value="BOTH">↕️ Both</option>
              <option value="BUY_ONLY">🟢 Buy Only</option>
              <option value="SELL_ONLY">🔴 Sell Only</option>
            </select>
          </div>
          
          <!-- Expandable Config (FULL INDEPENDENCE) -->
          <div v-if="slot.expanded && slot.enabled" class="p-3 border-t border-gray-700 space-y-3 bg-gray-850">
            <!-- Row 1: Timeframe + TSL -->
            <div class="grid grid-cols-2 gap-2">
              <div>
                <label class="text-[10px] text-gray-500">Timeframe</label>
                <select v-model="slot.timeframe" class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
                  <option value="M1">M1</option>
                  <option value="M5">M5</option>
                  <option value="M15">M15</option>
                  <option value="H1">H1</option>
                  <option value="H4">H4</option>
                </select>
              </div>
              <div>
                <label class="text-[10px] text-gray-500">TSL Mode</label>
                <select v-model="slot.tsl_mode" class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
                  <option value="OFF">Off</option>
                  <option value="ATR">ATR</option>
                  <option value="TIERED">Tiered</option>
                </select>
              </div>
            </div>
            
            <!-- Row 2: Risk/TP/SL -->
            <div class="grid grid-cols-3 gap-2">
              <div>
                <label class="text-[10px] text-gray-500">Risk%</label>
                <input type="number" v-model.number="slot.risk_percent" step="0.5" min="0.1" max="5" 
                       class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
              </div>
              <div>
                <label class="text-[10px] text-gray-500">TP R</label>
                <input type="number" v-model.number="slot.tp_ratio" step="0.5" min="1" max="5" 
                       class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
              </div>
              <div>
                <label class="text-[10px] text-gray-500">SL ATR</label>
                <input type="number" v-model.number="slot.sl_atr_multiplier" step="0.5" min="0.5" max="3" 
                       class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
              </div>
            </div>
            
            <!-- Row 3: RSI Settings -->
            <div class="grid grid-cols-3 gap-2">
              <div>
                <label class="text-[10px] text-gray-500">RSI Period</label>
                <input type="number" v-model.number="slot.rsi_period" min="5" max="21" 
                       class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
              </div>
              <div>
                <label class="text-[10px] text-gray-500">RSI OB</label>
                <input type="number" v-model.number="slot.rsi_overbought" min="60" max="90" 
                       class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
              </div>
              <div>
                <label class="text-[10px] text-gray-500">RSI OS</label>
                <input type="number" v-model.number="slot.rsi_oversold" min="10" max="40" 
                       class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
              </div>
            </div>
            
            <!-- Row 4: Min Confluence + Max Hours -->
            <div class="grid grid-cols-2 gap-2">
              <div>
                <label class="text-[10px] text-gray-500">Min Confluence</label>
                <input type="number" v-model.number="slot.min_confluence" min="3" max="10" 
                       class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
              </div>
              <div>
                <label class="text-[10px] text-gray-500">Max Hours (0=∞)</label>
                <input type="number" v-model.number="slot.max_duration" min="0" max="48" 
                       class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs">
              </div>
            </div>
            
            <!-- Row 5: Strategies -->
            <div class="grid grid-cols-2 gap-1 text-[10px]">
              <label class="flex items-center space-x-1">
                <input type="checkbox" v-model="slot.enable_vwap" class="h-3 w-3">
                <span class="text-gray-400">VWAP</span>
              </label>
              <label class="flex items-center space-x-1">
                <input type="checkbox" v-model="slot.enable_stoch" class="h-3 w-3">
                <span class="text-gray-400">Stoch</span>
              </label>
              <label class="flex items-center space-x-1">
                <input type="checkbox" v-model="slot.enable_institutional" class="h-3 w-3">
                <span class="text-gray-400">Inst.</span>
              </label>
              <label class="flex items-center space-x-1">
                <input type="checkbox" v-model="slot.enable_fibonacci" class="h-3 w-3">
                <span class="text-gray-400">Fib</span>
              </label>
            </div>
          </div>
          
          <!-- Progress / Results -->
          <div class="p-2 border-t border-gray-700">
            <div v-if="slot.isRunning" class="flex items-center space-x-2">
              <div class="flex-1 bg-gray-700 rounded-full h-1.5">
                <div class="bg-blue-500 h-1.5 rounded-full transition-all" :style="{ width: slot.progress + '%' }"></div>
              </div>
              <span class="text-xs text-blue-400">{{ slot.progress }}%</span>
            </div>
            <div v-else-if="slot.results?.win_rate" class="flex justify-between text-xs">
              <span :class="slot.results.net_profit >= 0 ? 'text-green-400' : 'text-red-400'">
                {{ slot.results.net_profit >= 0 ? '+' : '' }}${{ slot.results.net_profit?.toFixed(0) }}
              </span>
              <span class="text-gray-500">WR: {{ slot.results.win_rate?.toFixed(0) }}%</span>
            </div>
            <div v-else class="text-xs text-gray-600 text-center">Ready</div>
          </div>
        </div>
      </div>
    </div>

    <!-- Legacy Progress Bar (for single run compatibility) -->
    <div v-if="isRunning" class="w-full bg-gray-700 rounded-full h-2.5 mb-6">
      <div class="bg-blue-600 h-2.5 rounded-full transition-all duration-300" :style="{ width: progress + '%' }"></div>
    </div>


    <!-- Portfolio Settings (Shared: Dates + Balance) - BACKTEST ONLY -->
    <div v-if="tradingMode === 'backtest'" class="bg-gray-800 rounded-xl border border-gray-700 p-4 mb-6">
      <div class="flex justify-between items-center mb-3">
        <h3 class="text-sm font-semibold text-gray-300">📅 Portfolio Settings</h3>
        <span class="text-xs text-gray-500">Shared across all slots</span>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <label class="block text-xs text-gray-500 mb-1">Start Date</label>
          <input type="date" v-model="sharedConfig.start_date" 
                 class="w-full bg-gray-900 border border-gray-700 rounded px-3 py-2 text-white text-sm">
        </div>
        <div>
          <label class="block text-xs text-gray-500 mb-1">End Date</label>
          <input type="date" v-model="sharedConfig.end_date" 
                 class="w-full bg-gray-900 border border-gray-700 rounded px-3 py-2 text-white text-sm">
        </div>
        <div>
          <label class="block text-xs text-gray-500 mb-1">Start Balance ($)</label>
          <input type="number" v-model.number="sharedConfig.initial_balance" min="100" step="100"
                 class="w-full bg-gray-900 border border-gray-700 rounded px-3 py-2 text-white text-sm">
        </div>
      </div>
    </div>

    <!-- Live Account Info (LIVE MODE ONLY) -->
    <div v-if="tradingMode === 'live'" class="bg-gradient-to-r from-red-900/30 to-orange-900/30 rounded-xl border border-red-700 p-4 mb-6">
      <div class="flex justify-between items-center mb-3">
        <h3 class="text-sm font-semibold text-red-300">🔴 Live Account Info</h3>
        <span v-if="activeAccount" class="text-xs text-gray-400">Connected to {{ activeAccount.name }}</span>
        <span v-else class="text-xs text-red-400">⚠️ No account selected</span>
      </div>
      
      <div v-if="activeAccount" class="grid grid-cols-2 md:grid-cols-6 gap-4">
        <!-- Account Balance -->
        <div class="bg-gray-800/60 rounded-lg p-3 text-center">
          <div class="text-xs text-gray-500 mb-1">💰 Balance</div>
          <div class="text-lg font-bold text-green-400">${{ (activeAccount.starting_balance || 10000).toLocaleString() }}</div>
        </div>
        <!-- Login -->
        <div class="bg-gray-800/60 rounded-lg p-3 text-center">
          <div class="text-xs text-gray-500 mb-1">🔑 Login</div>
          <div class="text-sm font-bold text-white">{{ activeAccount.login }}</div>
        </div>
        <!-- Server -->
        <div class="bg-gray-800/60 rounded-lg p-3 text-center">
          <div class="text-xs text-gray-500 mb-1">🖥️ Server</div>
          <div class="text-xs font-bold text-white truncate">{{ activeAccount.server }}</div>
        </div>
        <!-- Total DD -->
        <div class="bg-gray-800/60 rounded-lg p-3 text-center">
          <div class="text-xs text-gray-500 mb-1">📉 Max DD</div>
          <div class="text-lg font-bold" :class="riskStatus.total_dd_percent > 5 ? 'text-red-400' : 'text-green-400'">
            {{ riskStatus.total_dd_percent?.toFixed(1) || 0 }}% / {{ activeAccount.max_drawdown_percent }}%
          </div>
        </div>
        <!-- Daily DD -->
        <div class="bg-gray-800/60 rounded-lg p-3 text-center">
          <div class="text-xs text-gray-500 mb-1">📊 Daily DD</div>
          <div class="text-lg font-bold" :class="riskStatus.daily_dd_percent > 2 ? 'text-orange-400' : 'text-green-400'">
            {{ riskStatus.daily_dd_percent?.toFixed(1) || 0 }}% / {{ activeAccount.max_daily_dd_percent }}%
          </div>
        </div>
        <!-- Account Type -->
        <div class="bg-gray-800/60 rounded-lg p-3 text-center">
          <div class="text-xs text-gray-500 mb-1">📋 Type</div>
          <div class="text-sm font-bold uppercase" 
               :class="{
                 'text-blue-400': activeAccount.account_type === 'demo',
                 'text-green-400': activeAccount.account_type === 'live',
                 'text-purple-400': activeAccount.account_type === 'prop'
               }">
            {{ activeAccount.account_type }}
          </div>
        </div>
      </div>
      
      <div v-else class="text-center py-6 text-gray-500">
        <div class="text-3xl mb-2">💳</div>
        <p>Please select an account from the dropdown above to start live trading.</p>
        <router-link to="/accounts" class="text-blue-400 hover:underline mt-2 inline-block">+ Add Account</router-link>
      </div>
    </div>

    <!-- Results Dashboard - Full Width -->
    <div class="space-y-4">
      
      <!-- PORTFOLIO COMBINED SUMMARY - BACKTEST ONLY -->
      <div v-if="tradingMode === 'backtest'" class="bg-gradient-to-r from-blue-900/40 to-purple-900/40 rounded-xl border border-blue-700 p-4">
        <div class="flex justify-between items-center mb-3">
          <h3 class="font-semibold text-white text-lg">📊 Portfolio Summary</h3>
          <span class="text-xs text-gray-400">Combined results from all {{ slots.filter(s => s.enabled).length }} slots</span>
        </div>
        <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
          <!-- Total Net Profit -->
          <div class="bg-gray-800/60 rounded-lg p-3 text-center">
            <div class="text-xs text-gray-500 mb-1">💰 Net Profit</div>
            <div class="text-xl font-bold" :class="portfolioMetrics.netProfit >= 0 ? 'text-green-400' : 'text-red-400'">
              {{ portfolioMetrics.netProfit >= 0 ? '+' : '' }}${{ portfolioMetrics.netProfit.toFixed(0) }}
            </div>
          </div>
          <!-- Combined Win Rate -->
          <div class="bg-gray-800/60 rounded-lg p-3 text-center">
            <div class="text-xs text-gray-500 mb-1">🎯 Win Rate</div>
            <div class="text-xl font-bold" :class="portfolioMetrics.winRate >= 50 ? 'text-green-400' : 'text-yellow-400'">
              {{ portfolioMetrics.winRate.toFixed(1) }}%
            </div>
          </div>
          <!-- Max Drawdown -->
          <div class="bg-gray-800/60 rounded-lg p-3 text-center">
            <div class="text-xs text-gray-500 mb-1">📉 Max DD</div>
            <div class="text-xl font-bold text-red-400">{{ portfolioMetrics.maxDrawdown.toFixed(1) }}%</div>
          </div>
          <!-- Total Trades -->
          <div class="bg-gray-800/60 rounded-lg p-3 text-center">
            <div class="text-xs text-gray-500 mb-1">📈 Total Trades</div>
            <div class="text-xl font-bold text-white">{{ portfolioMetrics.totalTrades }}</div>
          </div>
          <!-- Average Profit Factor -->
          <div class="bg-gray-800/60 rounded-lg p-3 text-center">
            <div class="text-xs text-gray-500 mb-1">⚖️ Profit Factor</div>
            <div class="text-xl font-bold" :class="portfolioMetrics.profitFactor >= 1.5 ? 'text-green-400' : 'text-yellow-400'">
              {{ portfolioMetrics.profitFactor.toFixed(2) }}
            </div>
          </div>
        </div>
      </div>
      
      <!-- Correlation & Risk Analysis Row -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
        <!-- Correlation Heatmap -->
        <CorrelationHeatmap :symbols="enabledSymbols" />
        
        <!-- Portfolio Risk Summary -->
        <div class="bg-gray-800 rounded-xl border border-gray-700 p-4">
          <h3 class="text-sm font-semibold text-gray-300 mb-3">⚠️ Portfolio Risk</h3>
          <div class="space-y-3">
            <div>
              <div class="flex justify-between text-xs mb-1">
                <span class="text-gray-500">Potential Risk</span>
                <span class="text-white">{{ totalPotentialRisk.toFixed(1) }}% / {{ portfolioSynergy.max_risk }}%</span>
              </div>
              <div class="w-full bg-gray-700 rounded-full h-2">
                <div 
                  class="h-2 rounded-full transition-all"
                  :class="totalPotentialRisk > portfolioSynergy.max_risk ? 'bg-red-500' : totalPotentialRisk > portfolioSynergy.max_risk * 0.8 ? 'bg-yellow-500' : 'bg-green-500'"
                  :style="{ width: Math.min(totalPotentialRisk / portfolioSynergy.max_risk * 100, 100) + '%' }"
                ></div>
              </div>
              <div class="text-xs text-gray-600 mt-1">Active: {{ totalActiveRisk.toFixed(1) }}%</div>
            </div>
            <div class="grid grid-cols-2 gap-2 text-xs">
              <div class="bg-gray-900 rounded p-2">
                <div class="text-gray-500">{{ tradingMode === 'live' ? 'Open Positions' : 'Total Trades' }}</div>
                <div class="text-lg font-bold text-white">{{ tradingMode === 'live' ? openPositionCount : portfolioMetrics.totalTrades }}</div>
              </div>
              <div class="bg-gray-900 rounded p-2">
                <div class="text-gray-500">Active Slots</div>
                <div class="text-lg font-bold text-blue-400">{{ slots.filter(s => s.enabled).length }}</div>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Per-Slot Results Grid (2x2) -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div v-for="slot in slots.filter(s => s.enabled)" :key="'result-' + slot.id" 
               class="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
            <!-- Slot Header with Symbol + Progress -->
            <div class="p-3 border-b border-gray-700 flex justify-between items-center">
              <div class="flex items-center space-x-2">
                <span class="text-white font-semibold">{{ slot.symbol }}</span>
                <span class="text-xs px-2 py-0.5 rounded"
                      :class="slot.direction === 'BUY_ONLY' ? 'bg-green-900 text-green-400' : 
                              slot.direction === 'SELL_ONLY' ? 'bg-red-900 text-red-400' : 
                              'bg-gray-700 text-gray-400'">
                  {{ slot.direction === 'BUY_ONLY' ? '🟢 BUY' : slot.direction === 'SELL_ONLY' ? '🔴 SELL' : '↕️' }}
                </span>
              </div>
              <div v-if="slot.isRunning" class="flex items-center space-x-2">
                <div class="w-20 bg-gray-700 rounded-full h-2">
                  <div class="bg-blue-500 h-2 rounded-full transition-all" :style="{ width: slot.progress + '%' }"></div>
                </div>
                <span class="text-xs text-blue-400">{{ slot.progress }}%</span>
              </div>
              <span v-else-if="slot.results?.total_trades" class="text-xs text-gray-500">
                {{ slot.results.total_trades }} trades
              </span>
            </div>
            
            <!-- Slot Metrics Row -->
            <div class="grid grid-cols-4 gap-2 p-3 bg-gray-850">
              <div class="text-center">
                <div class="text-[10px] text-gray-500">Net</div>
                <div class="text-sm font-bold" :class="(slot.results?.net_profit || 0) >= 0 ? 'text-green-400' : 'text-red-400'">
                  {{ slot.results?.net_profit ? (slot.results.net_profit >= 0 ? '+' : '') + '$' + slot.results.net_profit.toFixed(0) : '-' }}
                </div>
              </div>
              <div class="text-center">
                <div class="text-[10px] text-gray-500">WR</div>
                <div class="text-sm font-bold text-white">{{ slot.results?.win_rate ? slot.results.win_rate.toFixed(0) + '%' : '-' }}</div>
              </div>
              <div class="text-center">
                <div class="text-[10px] text-gray-500">PF</div>
                <div class="text-sm font-bold" :class="(slot.results?.profit_factor || 0) >= 1.5 ? 'text-green-400' : 'text-yellow-400'">
                  {{ slot.results?.profit_factor ? slot.results.profit_factor.toFixed(2) : '-' }}
                </div>
              </div>
              <div class="text-center">
                <div class="text-[10px] text-gray-500">DD</div>
                <div class="text-sm font-bold text-red-400">{{ slot.results?.max_drawdown ? slot.results.max_drawdown.toFixed(0) + '%' : '-' }}</div>
              </div>
            </div>
            
            <!-- Slot Mini Trade Table (last 5 trades) -->
            <div class="max-h-40 overflow-y-auto">
              <table class="w-full text-xs">
                <thead class="bg-gray-900 text-gray-500 sticky top-0">
                  <tr>
                    <th class="px-2 py-1 text-left">Time</th>
                    <th class="px-2 py-1">Type</th>
                    <th class="px-2 py-1 text-right">P/L</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-700">
                  <tr v-if="slot.trades.length === 0">
                    <td colspan="3" class="px-2 py-3 text-center text-gray-600">Waiting...</td>
                  </tr>
                  <tr v-for="trade in slot.trades.slice(0, 5)" :key="trade.id" class="text-gray-400">
                    <td class="px-2 py-1">{{ formatDateTime(trade.exit_time) }}</td>
                    <td class="px-2 py-1 text-center">
                      <span :class="trade.trade_type === 'BUY' ? 'text-green-400' : 'text-red-400'">{{ trade.trade_type }}</span>
                    </td>
                    <td class="px-2 py-1 text-right font-medium" :class="trade.profit >= 0 ? 'text-green-400' : 'text-red-400'">
                      {{ trade.profit >= 0 ? '+' : '' }}${{ trade.profit?.toFixed(0) }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Combined Trade History (All Slots) -->
        <div class="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
          <div class="p-4 border-b border-gray-700 flex justify-between items-center">
            <h3 class="font-semibold text-white">📋 All Trades</h3>
            <span class="text-xs text-gray-500">{{ trades.length }} total</span>
          </div>
          <div class="overflow-x-auto max-h-64">
            <table class="w-full text-left text-sm">
              <thead class="bg-gray-900 text-gray-400 sticky top-0">
                <tr>
                  <th class="px-3 py-2">Symbol</th>
                  <th class="px-3 py-2">Time</th>
                  <th class="px-3 py-2">Duration</th>
                  <th class="px-3 py-2">Type</th>
                  <th class="px-3 py-2 text-right">Profit</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-700">
                <tr v-if="trades.length === 0">
                  <td colspan="5" class="px-4 py-6 text-center text-gray-500">No trades yet</td>
                </tr>
                <tr v-for="trade in trades.slice(0, 20)" :key="trade.id" class="hover:bg-gray-750">
                  <td class="px-3 py-2 text-gray-300 text-xs">{{ trade.symbol || '-' }}</td>
                  <td class="px-3 py-2 text-gray-400 text-xs">{{ formatDateTime(trade.exit_time) }}</td>
                  <td class="px-3 py-2 text-xs">
                    <span :class="getDurationColor(trade.entry_time, trade.exit_time)">
                      {{ formatDuration(trade.entry_time, trade.exit_time) }}
                    </span>
                  </td>
                  <td class="px-3 py-2">
                    <span class="px-2 py-0.5 rounded text-xs font-medium"
                          :class="trade.trade_type === 'BUY' ? 'bg-green-900 text-green-400' : 'bg-red-900 text-red-400'">
                      {{ trade.trade_type }}
                    </span>
                  </td>
                  <td class="px-3 py-2 text-right font-medium" :class="trade.profit >= 0 ? 'text-green-400' : 'text-red-400'">
                    {{ trade.profit >= 0 ? '+' : '' }}${{ trade.profit?.toFixed(2) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import axios from 'axios'
import socket, { connectionState, connectSocket } from '../services/socket'
import CorrelationHeatmap from '../components/CorrelationHeatmap.vue'

// Socket connection state (reactive refs from socket.js)
const socketConnected = connectionState.isConnected
const socketReconnecting = connectionState.isReconnecting

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000'

// State
const isRunning = ref(false)  // Global running state (any slot running)
const history = ref([])

// Trading Mode State
const tradingMode = ref('backtest')  // 'backtest' or 'live'
const accounts = ref([])
const selectedAccountId = ref(null)
const activeAccount = computed(() => accounts.value.find(a => a.id === selectedAccountId.value))
const riskStatus = ref({ total_dd_percent: 0, daily_dd_percent: 0 })

// Fetch accounts for live trading
const fetchAccounts = async () => {
  try {
    const response = await axios.get(`${API_URL}/api/accounts/`)
    accounts.value = response.data
    // Auto-select active account
    const active = accounts.value.find(a => a.is_active)
    if (active) {
      selectedAccountId.value = active.id
    }
  } catch (error) {
    console.error('Failed to fetch accounts:', error)
  }
}

const onAccountChange = async () => {
  if (selectedAccountId.value && tradingMode.value === 'live') {
    try {
      await axios.post(`${API_URL}/api/accounts/${selectedAccountId.value}/connect`)
      await fetchAccounts()
    } catch (error) {
      console.error('Failed to connect account:', error)
    }
  }
}

// Stop all live trading sessions
const stopLiveTrading = async () => {
  try {
    await axios.post(`${API_URL}/api/trading/stop-all`)
    console.log('🛑 Stopped all live trading sessions')
    isRunning.value = false
    
    // Reset slot states
    slots.value.forEach(slot => {
      slot.isRunning = false
      slot.sessionId = null
    })
  } catch (error) {
    console.error('Failed to stop trading:', error)
  }
}

// Load open positions from MT5 and display in table
const loadOpenPositions = async () => {
  try {
    const response = await axios.get(`${API_URL}/api/market/positions`)
    const positions = response.data
    
    console.log('📊 Loaded positions:', positions)
    
    // Add each position to the trades table
    positions.forEach(pos => {
      const tradeObj = {
        id: pos.ticket,
        symbol: pos.symbol,
        entry_time: pos.open_time,
        exit_time: null,  // Still open
        trade_type: pos.type,  // 0=BUY, 1=SELL
        entry_price: pos.open_price,
        exit_price: null,
        stop_loss: pos.sl,
        take_profit: pos.tp,
        volume: pos.volume,
        profit: pos.profit,
        status: 'OPEN'
      }
      
      // Only add if not already in trades
      const exists = trades.value.find(t => t.id === pos.ticket)
      if (!exists) {
        trades.value.unshift(tradeObj)
      }
    })
    
    console.log('✅ Loaded', positions.length, 'open positions')
  } catch (error) {
    console.error('Failed to load positions:', error)
  }
}

// SYMBOL PRESETS - Complete configurations per symbol (based on research)
const symbolPresets = {
  'GBPJPY': { 
    name: 'GBP/JPY', emoji: '😈', volatility: 'HIGH',
    timeframe: 'M5', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.5, 
    rsi_period: 9, rsi_overbought: 75, rsi_oversold: 25, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Trade both directions for more opportunities
    description: 'The Beast 🔥 High volatility, strong trends' 
  },
  'EURUSD': { 
    name: 'EUR/USD', emoji: '💶', volatility: 'LOW',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.0, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Most liquid, ranges well both directions
    description: 'Most liquid - Tight stops, trade both directions' 
  },
  'XAUUSD': { 
    name: 'XAU/USD', emoji: '🥇', volatility: 'EXTREME',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 0.5, tp_ratio: 1.5, sl_atr_multiplier: 2.0, 
    rsi_period: 9, rsi_overbought: 80, rsi_oversold: 20, min_confluence: 5, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Trade both directions for more opportunities
    description: 'Gold 🥇 Extreme volatility - Wider stops' 
  },
  'USDJPY': { 
    name: 'USD/JPY', emoji: '🇯🇵', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.0, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Trade both directions for more opportunities
    description: 'Smooth trends - Tight SL, let profits run' 
  },
  'AUDJPY': { 
    name: 'AUD/JPY', emoji: '🦘', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.5, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: false, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Trade both directions for more opportunities
    description: 'Carry trade pair - Positive swap on long' 
  },
  'NZDJPY': { 
    name: 'NZD/JPY', emoji: '🥝', volatility: 'MEDIUM',
    timeframe: 'M15', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.5, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: false, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Trade both directions for more opportunities
    description: 'Carry trade pair - Positive swap on long' 
  },
  'EURCHF': { 
    name: 'EUR/CHF', emoji: '🇨🇭', volatility: 'LOW',
    timeframe: 'M15', tsl_mode: 'OFF',
    risk_percent: 1.5, tp_ratio: 1.5, sl_atr_multiplier: 0.75, 
    rsi_period: 14, rsi_overbought: 65, rsi_oversold: 35, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: false, enable_fibonacci: true,
    direction: 'BOTH',  // Range trading pair, both directions work
    description: 'Range Trading ↔️ Both directions - Low volatility' 
  },
  'EURGBP': { 
    name: 'EUR/GBP', emoji: '💶💷', volatility: 'LOW',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.0, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Channel 💶💷 Range trading - Low volatility' 
  },
  // ===== NEW PAIRS (Researched optimal settings 2024) =====
  'EURJPY': { 
    name: 'EUR/JPY', emoji: '🇪🇺🇯🇵', volatility: 'HIGH',
    timeframe: 'M5', tsl_mode: 'TIERED',  // High volatility needs tiered protection
    risk_percent: 0.75, tp_ratio: 2.0, sl_atr_multiplier: 1.5,  // Medium-tight stops
    rsi_period: 9, rsi_overbought: 75, rsi_oversold: 25, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // High volatility cross - trade both directions
    description: 'EUR/JPY 🔥 High volatility cross - Fast moves' 
  },
  'USDCHF': { 
    name: 'USD/CHF', emoji: '🇺🇸🇨🇭', volatility: 'LOW',
    timeframe: 'M5', tsl_mode: 'TIERED',  // Low volatility, TIERED mode
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.0,  // Tight stops for range trading
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Range pair, mirrors EURUSD inversely
    description: 'USD/CHF ↔️ Range trading - Mirrors EURUSD' 
  },
  // ===== LOW CORRELATION PAIRS FOR DIVERSIFICATION =====
  'AUDUSD': { 
    name: 'AUD/USD', emoji: '🦘', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'TIERED',  // Commodity pair, moderate volatility
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.5,  // Medium stops
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Commodity currency, moves independently of EUR/JPY
    description: 'AUD/USD 🦘 Commodity pair - Low correlation with majors' 
  },
  'USDCAD': { 
    name: 'USD/CAD', emoji: '🍁', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'TIERED',  // Oil-linked, moderate volatility
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.5,  // Medium stops
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Oil-linked, different drivers from EUR/JPY pairs
    description: 'USD/CAD 🍁 Oil-linked - Independent of European pairs' 
  },
  '#BTCUSD': { 
    name: 'Bitcoin', emoji: '₿', volatility: 'EXTREME',
    timeframe: 'M15', tsl_mode: 'TIERED',
    risk_percent: 0.5, tp_ratio: 2.0, sl_atr_multiplier: 2.0,  // Wide stops for crypto volatility
    rsi_period: 9, rsi_overbought: 75, rsi_oversold: 25, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // High volatility = trade both directions
    description: 'Bitcoin ₿ Extreme volatility - Wide stops, fast moves' 
  },
  'GBPUSD': { 
    name: 'GBP/USD', emoji: '💷', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.2, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Cable 💷 Strong trends - Liquid pair' 
  }
}

// Apply preset when symbol changes
const applySymbolPreset = (slot) => {
  const preset = symbolPresets[slot.symbol]
  if (preset) {
    slot.timeframe = preset.timeframe
    slot.tsl_mode = preset.tsl_mode
    slot.risk_percent = preset.risk_percent
    slot.tp_ratio = preset.tp_ratio
    slot.sl_atr_multiplier = preset.sl_atr_multiplier
    slot.rsi_period = preset.rsi_period
    slot.rsi_overbought = preset.rsi_overbought
    slot.rsi_oversold = preset.rsi_oversold
    slot.min_confluence = preset.min_confluence
    slot.max_duration = preset.max_duration
    slot.enable_vwap = preset.enable_vwap
    slot.enable_stoch = preset.enable_stoch
    slot.enable_institutional = preset.enable_institutional
    slot.enable_fibonacci = preset.enable_fibonacci
    slot.direction = preset.direction  // Apply researched direction bias
  }
}

// MULTI-SYMBOL SLOTS - Optimized for stability (M15 + H1 Conf + Wide Stops + NO Partial TP)
const slots = ref([
  { id: 0, symbol: 'EURJPY', enabled: true, expanded: true, isRunning: false, progress: 0, results: {}, trades: [], sessionId: null,
    // 🇪🇺🇯🇵 EURJPY: The Beast (Momentum)
    ...symbolPresets['EURJPY'], 
    risk_percent: 0.5, timeframe: 'H1', 
    tp_ratio: 2.0, sl_atr_multiplier: 1.2, 
    rsi_period: 9, rsi_overbought: 75, rsi_oversold: 25,
    tsl_mode: 'TIERED', use_h1_trend_filter: true, // ✅ Momentum: H1 Filter ON
    tsl_activation_r: 1.0, // Activate at 1R
    max_duration: 4, // Max hold 4 hours
    partial_tp_on: false, min_confluence_score: 7, description: 'The Beast Cross (H1 Momentum - Safe Mode)' },  
  { id: 1, symbol: 'GBPJPY', enabled: false, expanded: false, isRunning: false, progress: 0, results: {}, trades: [], sessionId: null,
    // 💷🇯🇵 GBPJPY: The Dragon
    ...symbolPresets['GBPJPY'], risk_percent: 0.75, timeframe: 'M5', tp_ratio: 2.0, sl_atr_multiplier: 1.5, partial_tp_on: false, min_confluence_score: 7, description: 'The Dragon Scalper' },  
  { id: 2, symbol: 'EURGBP', enabled: true, expanded: true, isRunning: false, progress: 0, results: {}, trades: [], sessionId: null,
    // 💶💷 EURGBP: The Channel (Range)
    ...symbolPresets['EURGBP'], 
    risk_percent: 0.7, timeframe: 'H1', 
    tp_ratio: 1.4, sl_atr_multiplier: 1.2, 
    rsi_period: 14, rsi_overbought: 60, rsi_oversold: 40,
    tsl_mode: 'ATR', tsl_atr_multiplier: 0.8, // Light trail
    use_h1_trend_filter: false, // ❌ Range: H1 Filter OFF
    stoch_k_period: 9, stoch_d_period: 3, vwap_use_trend_filter: false, // Range Settings
    max_duration: 4, // Max hold 4 hours
    partial_tp_on: false, min_confluence_score: 7, description: 'Channel Scalper (H1 Range - Safe Mode)' },  
  { id: 3, symbol: 'AUDJPY', enabled: false, expanded: false, isRunning: false, progress: 0, results: {}, trades: [], sessionId: null,
    // 🦘🇯🇵 AUDJPY: Risk Proxy
    ...symbolPresets['AUDJPY'], risk_percent: 0.75, timeframe: 'M5', tp_ratio: 2.0, sl_atr_multiplier: 1.5, partial_tp_on: false, min_confluence_score: 7, description: 'Risk Proxy Scalper' }   
])

// Portfolio Synergy Settings
const portfolioSynergy = ref({
  max_risk: 4.0,  // Max combined risk across all slots
  max_positions: 2  // Max positions per symbol
})

// Computed: Enabled symbols for correlation matrix
const enabledSymbols = computed(() => {
  return slots.value.filter(s => s.enabled).map(s => s.symbol)
})

// Computed: Total active risk (sum of risk % for slots with open positions)
const totalActiveRisk = computed(() => {
  return slots.value
    .filter(s => s.enabled && s.trades.some(t => t.status === 'OPEN' || !t.exit_time))
    .reduce((sum, s) => sum + (s.risk_percent || 1.0), 0)
})

// Computed: Total potential risk (sum of risk % for all enabled slots)
const totalPotentialRisk = computed(() => {
  return slots.value
    .filter(s => s.enabled)
    .reduce((sum, s) => sum + (s.risk_percent || 1.0), 0)
})

// Computed: Open position count
const openPositionCount = computed(() => {
  return slots.value.reduce((count, s) => {
    return count + s.trades.filter(t => t.status === 'OPEN' || !t.exit_time).length
  }, 0)
})

// PORTFOLIO COMBINED METRICS (computed from all enabled slots)
const portfolioMetrics = computed(() => {
  const enabledSlots = slots.value.filter(s => s.enabled)
  
  // Sum up all metrics
  let totalNetProfit = 0
  let totalTrades = 0
  let totalWins = 0
  let totalGrossProfit = 0
  let totalGrossLoss = 0
  let maxDrawdown = 0
  
  enabledSlots.forEach(slot => {
    // Prefer results if available (finalized stats), otherwise calc from trades
    const hasResults = slot.results && slot.results.total_trades !== undefined
    
    if (hasResults) {
      if (slot.results.total_trades) {
        totalTrades += slot.results.total_trades
        totalWins += Math.round(slot.results.total_trades * (slot.results.win_rate || 0) / 100)
      }
      if (slot.results.net_profit !== undefined) totalNetProfit += slot.results.net_profit
      if (slot.results.gross_profit) totalGrossProfit += slot.results.gross_profit
      if (slot.results.gross_loss) totalGrossLoss += Math.abs(slot.results.gross_loss)
      if (slot.results.max_drawdown && slot.results.max_drawdown > maxDrawdown) {
        maxDrawdown = slot.results.max_drawdown
      }
    } else if (slot.trades && slot.trades.length > 0) {
      // Fallback: Real-time calculation from trades list
      const closedTrades = slot.trades.filter(t => t.exit_time || t.status === 'CLOSED')
      
      totalTrades += closedTrades.length
      totalWins += closedTrades.filter(t => (t.profit || 0) > 0).length
      totalNetProfit += closedTrades.reduce((sum, t) => sum + (t.profit || 0), 0)
      
      let runningBalance = 0
      let peakBalance = 0
      let currentDrawdown = 0
      let slotMaxDrawdown = 0
      
      closedTrades.forEach(t => {
        const profit = t.profit || 0
        if (profit > 0) totalGrossProfit += profit
        else totalGrossLoss += Math.abs(profit)
        
        // Calculate Max DD from trade sequence
        runningBalance += profit
        if (runningBalance > peakBalance) peakBalance = runningBalance
        const dd = peakBalance - runningBalance
        if (dd > slotMaxDrawdown) slotMaxDrawdown = dd
      })
      
      // Convert absolute DD to approx % (assuming 10k or initial balance basis - simplistic for fallback)
      // Ideally backend sends this, but for fallback we take the largest absolute drop
      if (slotMaxDrawdown > 0) {
         // Use a rough estimate if balance div not available, or just track largest absolute drop
         // For portfolio view, we can track max relative DD if we knew starting balance
         // Here we'll just use the largest DD found this session
         if (slotMaxDrawdown > maxDrawdown) maxDrawdown = slotMaxDrawdown 
      }
    }
  })
  
  // Calculate combined metrics
  const winRate = totalTrades > 0 ? (totalWins / totalTrades * 100) : 0
  const profitFactor = totalGrossLoss > 0 ? (totalGrossProfit / totalGrossLoss) : (totalGrossProfit > 0 ? 999 : 0)
  
  return {
    netProfit: totalNetProfit,
    winRate: winRate,
    maxDrawdown: maxDrawdown,
    totalTrades: totalTrades,
    profitFactor: profitFactor
  }
})

// SHARED CONFIG (applies to all slots)
const sharedConfig = ref({
  timeframe: 'M5',
  confirmation_timeframe: null,
  strategy_mode: 'SCALP',
  start_date: '2024-01-01',
  end_date: '2024-04-10',
  initial_balance: 100000,
  risk_percent: 1.0,
  use_adx_filter: true,
  enable_vwap_strategy: true,
  enable_stoch_strategy: true,
  enable_institutional_strategy: true,
  enable_fibonacci_strategy: true,
  // RSI
  rsi_period: 9,
  rsi_overbought: 75,
  rsi_oversold: 25,
  // TSL
  enable_trailing_stop: true,
  tsl_mode: 'TIERED',
  tsl_activation_r: 0.0,
  // Partial TP
  partial_tp_on: true,
  partial_tp_amount: 1.0,
  // Scalping
  tp_ratio: 2.0,
  sl_atr_multiplier: 1.5,
  max_trade_duration_hours: 0,
  min_confluence_score: 7
})

// Legacy single-slot references for backward compatibility
const config = ref({
  symbol: 'GBPJPY',
  ...sharedConfig.value
})
const progress = ref(0)
const results = ref({})
const trades = ref([])

// High-volatility symbol detection
const HIGH_VOLATILITY_SYMBOLS = ['XAUUSD', 'BTCUSD', 'ETHUSD']

// Store previous risk before gold selection
let previousRiskBeforeGold = 1.0

// Handle symbol change - auto-reduce risk for high-volatility instruments
const onSymbolChange = () => {
  if (HIGH_VOLATILITY_SYMBOLS.includes(config.value.symbol)) {
    // Save current risk before reducing (only if not already reduced)
    if (config.value.risk_percent > 0.5) {
      previousRiskBeforeGold = config.value.risk_percent
    }
    // FORCE set risk to 0.5% for XAUUSD (backend will further reduce by 50% = 0.25%)
    config.value.risk_percent = 0.5
    console.log(`⚠️ Gold selected: Risk auto-reduced to ${config.value.risk_percent}% (backend applies 0.5x multiplier = ${config.value.risk_percent * 0.5}% effective)`)
  } else {
    // Restore previous risk when switching back to forex pairs
    if (config.value.risk_percent === 0.5 && previousRiskBeforeGold > 0.5) {
      config.value.risk_percent = previousRiskBeforeGold
    }
  }
}

// Handle timeframe change - auto-set strategy mode and reset confirmation TF
const onTimeframeChange = () => {
  // Reset confirmation timeframe to auto
  config.value.confirmation_timeframe = null
  
  // Auto-set strategy mode based on timeframe
  if (['M1', 'M5', 'M15'].includes(config.value.timeframe)) {
    config.value.strategy_mode = 'SCALP'
    // Lower confluence for scalping
    if (config.value.min_confluence_score > 6) {
      config.value.min_confluence_score = 5
    }
  } else {
    config.value.strategy_mode = 'SWING'
  }
}

// Get auto-detected HTF based on execution timeframe
const getAutoHTF = (tf) => {
  const htfMap = {
    'M1': 'M5',
    'M5': 'M15',
    'M15': 'H1',
    'H1': 'H4',
    'H4': 'D1'
  }
  return htfMap[tf] || 'H4'
}

// Methods
const runBacktest = async () => {
  // Get enabled slots
  const enabledSlots = slots.value.filter(s => s.enabled)
  if (enabledSlots.length === 0) {
    alert('Please enable at least one slot')
    return
  }
  
  // Check if live mode requires active account
  if (tradingMode.value === 'live' && !activeAccount.value) {
    alert('Please select an account to start live trading')
    return
  }
  
  isRunning.value = true
  
  // Reset all enabled slots
  enabledSlots.forEach(slot => {
    slot.isRunning = true
    slot.progress = 0
    slot.results = {}
    slot.trades = []
  })
  
  // Also reset legacy state
  trades.value = []
  results.value = {}
  progress.value = 0
  
  try {
    // Connect socket and WAIT for it to be connected before starting
    if (!socket.connected) {
      socket.connect()
      // Wait for socket to actually connect (up to 3 seconds)
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Socket connection timeout'))
        }, 3000)
        
        socket.once('connect', () => {
          clearTimeout(timeout)
          console.log('✅ Socket connected for live trading')
          resolve()
        })
        
        // If already connected, resolve immediately
        if (socket.connected) {
          clearTimeout(timeout)
          resolve()
        }
      })
    }
    
    // LIVE MODE - Start real trading
    if (tradingMode.value === 'live') {
      console.log('🔴 Starting LIVE TRADING mode...')
      
      const promises = enabledSlots.map(async (slot) => {
        // Build symbol - don't add prefix if symbol already has it
        const prefix = activeAccount.value?.symbol_prefix || ''
        const suffix = activeAccount.value?.symbol_suffix || ''
        let symbol = slot.symbol
        if (prefix && !symbol.startsWith(prefix)) {
          symbol = prefix + symbol
        }
        if (suffix && !symbol.endsWith(suffix)) {
          symbol = symbol + suffix
        }
        
        const payload = {
          symbol: symbol,
          direction_filter: slot.direction,
          risk_percent: slot.risk_percent,
          tp_ratio: slot.tp_ratio,
          sl_atr_multiplier: slot.sl_atr_multiplier,
          tsl_mode: slot.tsl_mode,
          timeframe: slot.timeframe,
          max_trade_duration_hours: slot.max_duration || 2,
          min_confluence_score: 5,
          account_id: activeAccount.value?.id
        }
        
        // Call live trading API
        const response = await axios.post(`${API_URL}/api/trading/start`, payload)
        slot.sessionId = response.data.session_id
        return response
      })
      
      await Promise.all(promises)
      console.log('🔴 Live trading started for', enabledSlots.length, 'slots')
      
    } else {
      // BACKTEST MODE - Run simulation
      console.log('📊 Starting BACKTEST mode...')
      
      const promises = enabledSlots.map(async (slot) => {
        // Merge shared config with slot-specific overrides
        const payload = {
          // Symbol and direction from slot
          symbol: slot.symbol,
          direction_filter: slot.direction,
          // Slot-specific settings (override shared)
          risk_percent: slot.risk_percent,
          tp_ratio: slot.tp_ratio,
          sl_atr_multiplier: slot.sl_atr_multiplier,
          enable_vwap_strategy: slot.enable_vwap,
          enable_stoch_strategy: slot.enable_stoch,
          enable_institutional_strategy: slot.enable_institutional,
          enable_fibonacci_strategy: slot.enable_fibonacci,
          // Slot-specific timeframe and TSL (FULL INDEPENDENCE)
          timeframe: slot.timeframe,
          tsl_mode: slot.tsl_mode,
          // Portfolio-level shared settings
          confirmation_timeframe: null,  // Auto-detect
          strategy_mode: ['M1', 'M5', 'M15'].includes(slot.timeframe) ? 'SCALP' : 'SWING',
          initial_balance: sharedConfig.value.initial_balance,
          use_adx_filter: slot.use_adx_filter !== undefined ? slot.use_adx_filter : true,
          use_h1_trend_filter: slot.use_h1_trend_filter !== undefined ? slot.use_h1_trend_filter : false,
          
          // New Stoch/VWAP
          stoch_k_period: slot.stoch_k_period || 14,
          stoch_d_period: slot.stoch_d_period || 3,
          vwap_use_trend_filter: slot.vwap_use_trend_filter !== undefined ? slot.vwap_use_trend_filter : true,

          rsi_period: slot.rsi_period || 14,
          rsi_overbought: slot.rsi_overbought || 70,
          rsi_oversold: slot.rsi_oversold || 30,
          enable_trailing_stop: slot.tsl_mode !== 'OFF',
          tsl_mode: slot.tsl_mode,
          tsl_atr_multiplier: slot.tsl_atr_multiplier || 1.5,
          tsl_activation_r: slot.tsl_activation_r || 0.0, 
          partial_tp_on: slot.partial_tp_on !== undefined ? slot.partial_tp_on : true,
          partial_tp_amount: 1.0,
          max_trade_duration_hours: slot.max_duration || 2,
          min_confluence_score: slot.min_confluence || 5,
          start_date: new Date(sharedConfig.value.start_date).toISOString(),
          end_date: new Date(sharedConfig.value.end_date).toISOString()
        }
        
        const response = await axios.post(`${API_URL}/api/backtest/run`, payload)
        slot.sessionId = response.data.session_id
        return response
      })
      
      await Promise.all(promises)
    }
    
  } catch (error) {
    console.error('Trading failed:', error)
    alert('Failed to start: ' + (error.response?.data?.detail || error.message))
    isRunning.value = false
    enabledSlots.forEach(slot => slot.isRunning = false)
  }
}

// Socket Event Listeners
const setupSocketListeners = () => {
    socket.on('backtest_progress', (data) => {
        // Find slot by session_id
        const slot = slots.value.find(s => s.sessionId === data.session_id)
        if (slot) {
            slot.progress = Math.round(data.progress)
            if (data.stats) {
                slot.results = {
                    ...slot.results,
                    net_profit: data.stats.balance - sharedConfig.value.initial_balance,
                    total_trades: data.stats.trades,
                }
            }
        }
        // Also update legacy progress (average of all running slots)
        const runningSlots = slots.value.filter(s => s.isRunning)
        if (runningSlots.length > 0) {
            progress.value = Math.round(runningSlots.reduce((sum, s) => sum + s.progress, 0) / runningSlots.length)
        }
    })

    socket.on('backtest_trade', (data) => {
        const trade = data.trade
        const slot = slots.value.find(s => s.sessionId === data.session_id)
        
        if (trade.type === 'CLOSE') {
            const tradeObj = {
                id: Date.now() + Math.random(),
                symbol: slot?.symbol || '-',  // Include symbol for combined table
                entry_time: trade.entry_time,
                exit_time: trade.exit_time,
                trade_type: trade.trade_type,
                entry_price: trade.entry_price,
                exit_price: trade.price,
                profit: trade.pnl,
                balance_after: trade.balance
            }
            
            // Add to slot's trades
            if (slot) {
                slot.trades.unshift(tradeObj)
                slot.results.net_profit = trade.balance - sharedConfig.value.initial_balance
            }
            
            // Also add to legacy trades
            trades.value.unshift(tradeObj)
            results.value.net_profit = trade.balance - sharedConfig.value.initial_balance
        }
    })

    socket.on('backtest_complete', (data) => {
        // Find and update the specific slot
        const slot = slots.value.find(s => s.sessionId === data.session_id)
        if (slot) {
            slot.isRunning = false
            slot.progress = 100
            slot.results = data.results
        }
        
        // Check if all slots are done
        const anyRunning = slots.value.some(s => s.isRunning)
        if (!anyRunning) {
            isRunning.value = false
            progress.value = 100
            fetchHistory()
        }
        
        // Update legacy results with first completed slot
        if (Object.keys(results.value).length === 0) {
            results.value = data.results
        }
    })
    
    // 🔴 LIVE TRADING: Handle real-time trade updates
    socket.on('live_trade_opened', (trade) => {
        console.log('🔴 Live trade opened:', trade)
        
        // Find the slot by session_id
        const slot = slots.value.find(s => s.sessionId === trade.session_id)
        
        const tradeObj = {
            id: trade.ticket,
            symbol: trade.symbol,
            entry_time: trade.opened_at,
            exit_time: null,  // Still open
            trade_type: trade.type,
            entry_price: trade.entry_price,
            exit_price: null,  // Still open
            stop_loss: trade.stop_loss,
            take_profit: trade.take_profit,
            volume: trade.volume,
            profit: 0,  // Unknown until closed
            status: 'OPEN'
        }
        
        // Add to slot's trades
        if (slot) {
            if (!slot.trades) slot.trades = []
            slot.trades.unshift(tradeObj)
        }
        
        // Add to legacy trades for combined view
        trades.value.unshift(tradeObj)
    })
    
    // 🔴 LIVE TRADING: Handle trade closed
    socket.on('live_trade_closed', (data) => {
        console.log('🔴 Live trade closed:', data)
        
        // Update trade in slot
        const slot = slots.value.find(s => s.sessionId === data.session_id)
        if (slot) {
            const trade = slot.trades.find(t => t.id === data.ticket)
            if (trade) {
                trade.status = 'CLOSED'
                trade.exit_time = data.closed_at
                trade.profit = data.pnl
            }
        }
        
        // Also update in legacy trades
        const legacyTrade = trades.value.find(t => t.id === data.ticket)
        if (legacyTrade) {
            legacyTrade.status = 'CLOSED'
            legacyTrade.exit_time = data.closed_at
            legacyTrade.profit = data.pnl
        }
    })
    
    // 🔴 LIVE TRADING: Handle trailing stop moved
    socket.on('trailing_stop_moved', (data) => {
        console.log('📈 Trailing SL moved:', data)
        
        // Update trade SL in slot
        const slot = slots.value.find(s => s.sessionId === data.session_id)
        if (slot) {
            const trade = slot.trades.find(t => t.id === data.ticket)
            if (trade) {
                trade.stop_loss = data.new_sl
            }
        }
    })
    
    // 🔴 LIVE TRADING: Handle market updates (account + positions)
    socket.on('market_update', (data) => {
        // Only process in live mode
        if (tradingMode.value !== 'live') return
        
        // Update position P&L in real-time
        if (data.positions) {
            data.positions.forEach(pos => {
                // Find matching trade across all slots
                slots.value.forEach(slot => {
                    const trade = slot.trades?.find(t => t.id === pos.ticket)
                    if (trade) {
                        trade.profit = pos.profit
                        trade.current_price = pos.price_current
                    }
                })
                
                // Also update legacy trades
                const legacyTrade = trades.value.find(t => t.id === pos.ticket)
                if (legacyTrade) {
                    legacyTrade.profit = pos.profit
                }
            })
        }
    })
}

const fetchHistory = async () => {
  try {
    const response = await axios.get('http://localhost:8000/api/backtest/history')
    history.value = response.data
  } catch (error) {
    console.error('Error fetching history:', error)
  }
}

// ==================== SLOT CRUD METHODS ====================

// Add a new slot
const addSlot = () => {
  const newId = Math.max(...slots.value.map(s => s.id)) + 1
  const defaultPreset = symbolPresets['EURUSD']
  
  slots.value.push({
    id: newId,
    dbId: null,  // Will be set when saved to DB
    symbol: 'EURUSD',
    enabled: true,
    expanded: true,
    isRunning: false,
    progress: 0,
    results: {},
    trades: [],
    sessionId: null,
    ...defaultPreset,
    direction: 'BOTH',
    risk_percent: 1.0,
    timeframe: 'M5',
    tp_ratio: 2.0,
    sl_atr_multiplier: 1.5,
    rsi_period: 14,
    rsi_overbought: 70,
    rsi_oversold: 30,
    min_confluence: 7,
    max_duration: 2,
    enable_vwap: true,
    enable_stoch: true,
    enable_institutional: true,
    enable_fibonacci: true,
    tsl_mode: 'TIERED',
    partial_tp_on: true
  })
  
  console.log(`➕ Added new slot ${newId}`)
}

// Delete a slot
const deleteSlot = async (slotId) => {
  const slot = slots.value.find(s => s.id === slotId)
  if (!slot) return
  
  // If slot has DB id, delete from server
  if (slot.dbId) {
    try {
      await axios.delete(`${API_URL}/api/slots/${slot.dbId}`)
      console.log(`🗑️ Deleted slot ${slot.dbId} from server`)
    } catch (error) {
      console.error('Failed to delete slot from server:', error)
    }
  }
  
  // Remove from local state
  slots.value = slots.value.filter(s => s.id !== slotId)
  console.log(`🗑️ Removed slot ${slotId}`)
}

// Save a single slot to DB (debounced)
let saveTimeout = null
const saveSlot = async (slot) => {
  // Debounce saves
  if (saveTimeout) clearTimeout(saveTimeout)
  
  saveTimeout = setTimeout(async () => {
    try {
      const payload = {
        bot_config_id: 1,  // Default config ID
        symbol: slot.symbol,
        direction_filter: slot.direction || 'BOTH',
        timeframe: slot.timeframe || 'M5',
        risk_percent: slot.risk_percent || 1.0,
        tp_ratio: slot.tp_ratio || 2.0,
        sl_atr_multiplier: slot.sl_atr_multiplier || 1.5,
        tsl_mode: slot.tsl_mode || 'TIERED',
        rsi_period: slot.rsi_period || 14,
        rsi_overbought: slot.rsi_overbought || 70,
        rsi_oversold: slot.rsi_oversold || 30,
        min_confluence_score: slot.min_confluence || 7,
        max_trade_duration_hours: slot.max_duration || 0,
        enable_vwap_strategy: slot.enable_vwap !== false,
        enable_stoch_strategy: slot.enable_stoch !== false,
        enable_institutional_strategy: slot.enable_institutional !== false,
        enable_fibonacci_strategy: slot.enable_fibonacci !== false,
        partial_tp_on: slot.partial_tp_on !== false,
        partial_tp_amount: 1.0,
        enabled: slot.enabled !== false
      }
      
      if (slot.dbId) {
        // Update existing
        await axios.put(`${API_URL}/api/slots/${slot.dbId}`, payload)
        console.log(`💾 Updated slot ${slot.dbId}`)
      } else {
        // Create new
        const response = await axios.post(`${API_URL}/api/slots/`, payload)
        slot.dbId = response.data.id
        console.log(`💾 Created slot ${slot.dbId}`)
      }
    } catch (error) {
      console.error('Failed to save slot:', error)
    }
  }, 500)  // 500ms debounce
}

// Load slots from database
const loadSlots = async () => {
  try {
    const response = await axios.get(`${API_URL}/api/slots/`)
    const dbSlots = response.data
    
    if (dbSlots.length > 0) {
      // Replace local slots with DB slots
      slots.value = dbSlots.map((dbSlot, index) => ({
        id: index,
        dbId: dbSlot.id,
        symbol: dbSlot.symbol,
        enabled: dbSlot.enabled,
        expanded: index === 0,  // First slot expanded
        isRunning: false,
        progress: 0,
        results: {},
        trades: [],
        sessionId: null,
        direction: dbSlot.direction_filter,
        timeframe: dbSlot.timeframe,
        risk_percent: dbSlot.risk_percent,
        tp_ratio: dbSlot.tp_ratio,
        sl_atr_multiplier: dbSlot.sl_atr_multiplier,
        tsl_mode: dbSlot.tsl_mode,
        rsi_period: dbSlot.rsi_period,
        rsi_overbought: dbSlot.rsi_overbought,
        rsi_oversold: dbSlot.rsi_oversold,
        min_confluence: dbSlot.min_confluence_score,
        max_duration: dbSlot.max_trade_duration_hours,
        enable_vwap: dbSlot.enable_vwap_strategy,
        enable_stoch: dbSlot.enable_stoch_strategy,
        enable_institutional: dbSlot.enable_institutional_strategy,
        enable_fibonacci: dbSlot.enable_fibonacci_strategy,
        partial_tp_on: dbSlot.partial_tp_on
      }))
      console.log(`📦 Loaded ${dbSlots.length} slots from database`)
    }
  } catch (error) {
    console.error('Failed to load slots from database:', error)
  }
}

const loadSession = async (sessionId) => {
  try {
    const response = await axios.get(`http://localhost:8000/api/backtest/${sessionId}`)
    results.value = response.data.session
    trades.value = response.data.trades
    // Update config to match loaded session (optional)
  } catch (error) {
    console.error('Error loading session:', error)
  }
}

const formatDate = (dateStr) => {
  return new Date(dateStr).toLocaleString()
}

// Compact date/time for table (MM/DD HH:MM)
const formatDateTime = (dateStr) => {
  if (!dateStr) return '-'
  const d = new Date(dateStr)
  return `${d.getMonth()+1}/${d.getDate()} ${d.getHours().toString().padStart(2,'0')}:${d.getMinutes().toString().padStart(2,'0')}`
}

// Format duration in human-readable format
const formatDuration = (startStr, endStr) => {
  if (!startStr || !endStr) return '-'
  const start = new Date(startStr)
  const end = new Date(endStr)
  const diffMs = end - start
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMins / 60)
  const diffDays = Math.floor(diffHours / 24)
  
  if (diffDays > 0) return `${diffDays}d ${diffHours % 24}h`
  if (diffHours > 0) return `${diffHours}h ${diffMins % 60}m`
  if (diffMins > 0) return `${diffMins}m`
  return `${Math.floor(diffMs / 1000)}s`
}

// Color code duration - green for fast scalps, yellow for medium, red for slow
const getDurationColor = (startStr, endStr) => {
  if (!startStr || !endStr) return 'text-gray-400'
  const start = new Date(startStr)
  const end = new Date(endStr)
  const diffMins = (end - start) / 60000
  
  if (diffMins < 30) return 'text-green-400'  // Scalp: < 30 min = excellent
  if (diffMins < 240) return 'text-yellow-400'  // Day trade: < 4 hours = ok
  return 'text-red-400'  // > 4 hours = too slow for scalping
}

const getPfColor = (pf) => {
  if (!pf) return 'text-gray-400'
  if (pf >= 1.5) return 'text-green-400'
  if (pf >= 1.0) return 'text-blue-400'
  return 'text-red-400'
}

const getTslModeDescription = (mode) => {
  const descriptions = {
    'FIXED': 'Trail at fixed R-multiple distance from price',
    'ATR': 'Trail at ATR × Multiplier (adapts to volatility)',
    'CHANDELIER': 'Trail from highest high/lowest low using ATR',
    'TIERED': 'Lock profit at 0.8R→BE, 1.5R→+0.8R, 2R→+1.2R',
    'SWING': 'Trail behind recent swing highs/lows',
    'PSAR': 'Parabolic SAR with accelerating factor'
  }
  return descriptions[mode] || ''
}

const getConfluenceDescription = (score) => {
  if (score >= 10) return '💎 Elite only - Institutional Sweep signals'
  if (score >= 9) return '⭐ Strong signals - Trend Following + Institutional'
  if (score >= 8) return '📈 Good signals - VWAP + Breakout included'
  if (score >= 7) return '📊 Medium signals - Range + most strategies'
  if (score >= 5) return '⚠️ Includes weak signals - more trades, lower quality'
  return '❌ All signals - high risk, many false positives'
}

// Init
onMounted(() => {
  connectSocket()  // Connect socket since autoConnect is false
  fetchHistory()
  setupSocketListeners()
  fetchAccounts()  // Load accounts for live trading mode
  loadSlots()  // Load slots from database
})

// Export combined portfolio trades to CSV
const exportPortfolioCSV = () => {
  // 1. Gather all trades from enabled slots
  const allTrades = []
  slots.value.filter(s => s.enabled).forEach(slot => {
    if (slot.trades && slot.trades.length > 0) {
      slot.trades.forEach(trade => {
        allTrades.push({
          ...trade,
          symbol: slot.symbol,
          slot_id: slot.id
        })
      })
    }
  })
  
  if (allTrades.length === 0) {
    alert('No trades to export.')
    return
  }
  
  // 2. Sort by entry time
  allTrades.sort((a, b) => new Date(a.entry_time) - new Date(b.entry_time))
  
  // 3. Generate CSV content
  const headers = ['Symbol', 'Ticket', 'Type', 'Entry Time', 'Exit Time', 'Entry Price', 'Exit Price', 'Profit', 'Duration (min)', 'Confluence']
  const rows = allTrades.map(t => [
    t.symbol,
    t.ticket || '',
    t.trade_type,
    t.entry_time,
    t.exit_time || 'OPEN',
    t.entry_price,
    t.exit_price || '',
    (t.profit || 0).toFixed(2),
    t.duration || '',
    t.confluence_score || ''
  ])
  
  const csvContent = [
    headers.join(','),
    ...rows.map(row => row.join(','))
  ].join('\n')
  
  // 4. Download file
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' })
  const link = document.createElement('a')
  const url = URL.createObjectURL(blob)
  link.setAttribute('href', url)
  link.setAttribute('download', `portfolio_backtest_${new Date().toISOString().slice(0,10)}.csv`)
  link.style.visibility = 'hidden'
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
}

onUnmounted(() => {
    // Backtest events
    socket.off('backtest_progress')
    socket.off('backtest_trade')
    socket.off('backtest_complete')
    // Live trading events
    socket.off('live_trade_opened')
    socket.off('live_trade_closed')
    socket.off('trailing_stop_moved')
    socket.off('market_update')
})
</script>
