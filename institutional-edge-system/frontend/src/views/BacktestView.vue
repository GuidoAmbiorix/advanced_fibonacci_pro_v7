<template>
  <div class="p-6 space-y-6 min-h-screen bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900">
    
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- 🎨 MODERN KPI DASHBOARD HEADER (Glassmorphism + Gradients)              -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- 🎨 DASHBOARD HEADER (Controls + KPIs)                                   -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <DashboardHeader
      v-model="tradingMode"
      v-model:selectedAccountId="selectedAccountId"
      :accounts="accounts"
      :kill-switch-active="killSwitchActive"
      :socket-connected="socketConnected"
      :socket-reconnecting="socketReconnecting"
      :portfolio-metrics="portfolioMetrics"
      :risk-status="riskStatus"
      :active-account="activeAccount"
      :shared-config="sharedConfig"
      :slots="slots"
      :portfolio-synergy="portfolioSynergy"
      :total-potential-risk="totalPotentialRisk"
      @toggle-kill-switch="toggleKillSwitch"
      @account-change="onAccountChange"
    />

    <!-- Header -->
    <div class="flex justify-between items-center">
      <div class="flex-1">
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold text-white">{{ tradingMode === 'backtest' ? 'Strategy Backtester' : '🔴 Live Trading' }}</h1>

          <!-- Socket Status Indicator -->
          <div class="flex items-center gap-2 px-3 py-1 rounded-full text-xs" :class="socketConnected ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'">
            <span class="relative flex h-2 w-2">
              <span v-if="socketConnected" class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-2 w-2" :class="socketConnected ? 'bg-green-500' : 'bg-red-500'"></span>
            </span>
            {{ socketConnected ? 'Connected' : 'Disconnected' }}
          </div>

          <!-- Backtest Status Badge -->
          <div v-if="backtestStatus && isRunning" class="flex items-center gap-2 px-3 py-1 rounded-full text-xs bg-blue-500/20 text-blue-400">
            <span class="animate-spin">⟳</span>
            {{ backtestStatus }}
          </div>
        </div>
        <p class="text-gray-400 mt-1">{{ tradingMode === 'backtest' ? 'Test strategies with historical data before going live' : 'Trading live with real money - FundedPips rules active' }}</p>
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
        <!-- 🆕 MANUAL TRADE BUTTON (Live mode only) -->
        <button 
          v-if="tradingMode === 'live'"
          @click="showManualTradeModal = true"
          :disabled="!activeAccount"
          class="px-4 py-2 bg-gradient-to-r from-yellow-600 to-orange-500 hover:from-yellow-500 hover:to-orange-400 text-white rounded-lg font-semibold flex items-center transition-all shadow-lg shadow-yellow-500/20 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          🎯 Manual Trade
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
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- 🎰 PORTFOLIO SLOTS                                                      -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <SlotManager
      :slots="slots"
      :shared-config="sharedConfig"
      :portfolio-synergy="portfolioSynergy"
      @add-slot="addSlot"
      @save-slot="saveSlot"
      @clone-slot="cloneSlot"
      @delete-slot="deleteSlot"
      @apply-preset="applySymbolPreset"
    />

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
      <KpiDashboard 
        v-if="tradingMode === 'backtest'" 
        :metrics="portfolioMetrics" 
        :tradingMode="tradingMode"
        :slotCount="slots.filter(s => s.enabled).length"
      />
      

      
      <!-- Correlation & Risk Analysis Row -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
        <!-- Correlation Heatmap -->
        <CorrelationHeatmap :symbols="enabledSymbols" />
        
        <!-- Portfolio Risk Summary -->
        <RiskOverview
          :total-potential-risk="totalPotentialRisk"
          :portfolio-synergy="portfolioSynergy"
          :total-active-risk="totalActiveRisk"
          :trading-mode="tradingMode"
          :open-position-count="openPositionCount"
          :metrics="portfolioMetrics"
          :active-slot-count="slots.filter(s => s.enabled).length"
        />
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
        <!-- Combined Trade History (All Slots) -->
        <TradeHistoryTable 
          :trades="trades"
          :format-date-time="formatDateTime"
          :format-duration="formatDuration"
          :get-duration-color="getDurationColor"
        />

        <!-- Backtest Logs Panel -->
        <BacktestLogs :session-id="currentSessionId" />
    </div>

    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- 🔔 TOAST NOTIFICATION                                                    -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <transition
      enter-active-class="transform ease-out duration-300 transition"
      enter-from-class="translate-y-2 opacity-0 sm:translate-y-0 sm:translate-x-2"
      enter-to-class="translate-y-0 opacity-100 sm:translate-x-0"
      leave-active-class="transition ease-in duration-200"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div v-if="showToast" class="fixed bottom-6 right-6 z-50 max-w-md">
        <div class="relative overflow-hidden rounded-xl border backdrop-blur-xl shadow-2xl"
             :class="{
               'bg-green-500/10 border-green-500/30': toastType === 'success',
               'bg-red-500/10 border-red-500/30': toastType === 'error',
               'bg-blue-500/10 border-blue-500/30': toastType === 'info',
               'bg-yellow-500/10 border-yellow-500/30': toastType === 'warning'
             }">
          <!-- Animated gradient bar -->
          <div class="absolute top-0 left-0 right-0 h-1">
            <div class="h-full animate-pulse"
                 :class="{
                   'bg-gradient-to-r from-green-500 to-emerald-400': toastType === 'success',
                   'bg-gradient-to-r from-red-500 to-rose-400': toastType === 'error',
                   'bg-gradient-to-r from-blue-500 to-cyan-400': toastType === 'info',
                   'bg-gradient-to-r from-yellow-500 to-amber-400': toastType === 'warning'
                 }">
            </div>
          </div>

          <div class="p-4 flex items-start gap-3">
            <!-- Icon -->
            <div class="flex-shrink-0 text-2xl">
              <span v-if="toastType === 'success'">✅</span>
              <span v-else-if="toastType === 'error'">❌</span>
              <span v-else-if="toastType === 'info'">ℹ️</span>
              <span v-else-if="toastType === 'warning'">⚠️</span>
            </div>

            <!-- Message -->
            <div class="flex-1 pt-0.5">
              <p class="text-sm font-medium"
                 :class="{
                   'text-green-300': toastType === 'success',
                   'text-red-300': toastType === 'error',
                   'text-blue-300': toastType === 'info',
                   'text-yellow-300': toastType === 'warning'
                 }">
                {{ toastMessage }}
              </p>
            </div>

            <!-- Close Button -->
            <button @click="showToast = false"
                    class="flex-shrink-0 rounded-lg p-1 transition-colors hover:bg-white/10">
              <svg class="w-4 h-4 text-gray-400 hover:text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
      </div>
    </transition>

    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- 🎯 MANUAL TRADE MODAL                                                   -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <transition name="modal">
      <div v-if="showManualTradeModal" 
           class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm"
           @click.self="showManualTradeModal = false">
        <div class="bg-gradient-to-br from-gray-900 to-gray-800 rounded-2xl border border-gray-700 shadow-2xl w-full max-w-md mx-4 overflow-hidden">
          <!-- Header -->
          <div class="px-6 py-4 border-b border-gray-700 bg-gradient-to-r from-yellow-600/20 to-orange-600/20">
            <h3 class="text-xl font-bold text-white flex items-center gap-2">
              🎯 Manual Trade
            </h3>
            <p class="text-sm text-gray-400 mt-1">Execute immediate market order</p>
          </div>
          
          <!-- Form -->
          <div class="p-6 space-y-4">
            <!-- Symbol -->
            <div>
              <label class="block text-sm text-gray-400 mb-1">Symbol</label>
              <select v-model="manualTradeForm.symbol"
                      class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:border-yellow-500 focus:outline-none">
                <option value="XAUUSD">🥇 XAUUSD (Gold)</option>
                <option value="EURUSD">💶 EURUSD</option>
                <option value="GBPUSD">💷 GBPUSD</option>
                <option value="USDJPY">💴 USDJPY</option>
                <option value="GBPJPY">😈 GBPJPY</option>
                <option value="BTCUSD">₿ BTCUSD</option>
              </select>
            </div>
            
            <!-- Order Type -->
            <div>
              <label class="block text-sm text-gray-400 mb-1">Order Type</label>
              <div class="grid grid-cols-2 gap-2">
                <button @click="manualTradeForm.orderType = 'BUY'"
                        class="py-3 rounded-lg font-bold text-lg transition-all"
                        :class="manualTradeForm.orderType === 'BUY' 
                          ? 'bg-gradient-to-r from-green-600 to-emerald-500 text-white shadow-lg shadow-green-500/30' 
                          : 'bg-gray-800 text-gray-400 hover:bg-gray-700'">
                  📈 BUY
                </button>
                <button @click="manualTradeForm.orderType = 'SELL'"
                        class="py-3 rounded-lg font-bold text-lg transition-all"
                        :class="manualTradeForm.orderType === 'SELL' 
                          ? 'bg-gradient-to-r from-red-600 to-rose-500 text-white shadow-lg shadow-red-500/30' 
                          : 'bg-gray-800 text-gray-400 hover:bg-gray-700'">
                  📉 SELL
                </button>
              </div>
            </div>
            
            <!-- Volume -->
            <div>
              <label class="block text-sm text-gray-400 mb-1">Volume (Lots)</label>
              <input type="number" v-model.number="manualTradeForm.volume"
                     step="0.01" min="0.01" max="10"
                     class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:border-yellow-500 focus:outline-none">
            </div>
            
            <!-- SL/TP (Optional) -->
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm text-gray-400 mb-1">Stop Loss (0 = none)</label>
                <input type="number" v-model.number="manualTradeForm.stopLoss"
                       step="0.01"
                       class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:border-yellow-500 focus:outline-none">
              </div>
              <div>
                <label class="block text-sm text-gray-400 mb-1">Take Profit (0 = none)</label>
                <input type="number" v-model.number="manualTradeForm.takeProfit"
                       step="0.01"
                       class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:border-yellow-500 focus:outline-none">
              </div>
            </div>
          </div>
          
          <!-- Actions -->
          <div class="px-6 py-4 border-t border-gray-700 flex justify-end gap-3">
            <button @click="showManualTradeModal = false"
                    class="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded-lg transition-colors">
              Cancel
            </button>
            <button @click="executeManualTrade"
                    :disabled="manualTradeLoading"
                    class="px-6 py-2 font-bold rounded-lg transition-all disabled:opacity-50"
                    :class="manualTradeForm.orderType === 'BUY' 
                      ? 'bg-gradient-to-r from-green-600 to-emerald-500 hover:from-green-500 hover:to-emerald-400 text-white' 
                      : 'bg-gradient-to-r from-red-600 to-rose-500 hover:from-red-500 hover:to-rose-400 text-white'">
              <span v-if="manualTradeLoading" class="animate-spin mr-2">⟳</span>
              {{ manualTradeLoading ? 'Executing...' : `Execute ${manualTradeForm.orderType}` }}
            </button>
          </div>
        </div>
      </div>
    </transition>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import axios from 'axios'
import { useSocketTrading } from '../composables/useSocketTrading'
import { usePortfolioMetrics } from '../composables/usePortfolioMetrics'
import { useRiskManagement } from '../composables/useRiskManagement'
import socket, { connectionState } from '../services/socket'

import CorrelationHeatmap from '../components/CorrelationHeatmap.vue'
import BacktestLogs from '../components/BacktestLogs.vue'
import DashboardHeader from '../components/backtest/DashboardHeader.vue'
import SlotManager from '../components/backtest/SlotManager.vue'
import RiskOverview from '../components/backtest/RiskOverview.vue'
import KpiDashboard from '../components/backtest/KpiDashboard.vue'
import TradeHistoryTable from '../components/backtest/TradeHistoryTable.vue'
import { useSlotManager } from '../composables/useSlotManager'

// Socket connection state (reactive refs from socket.js)
const socketConnected = connectionState.isConnected
const socketReconnecting = connectionState.isReconnecting

// Use relative path for proxy support
const API_URL = import.meta.env.VITE_API_BASE_URL || ''

// State
const isRunning = ref(false)  // Global running state (any slot running)
const progress = ref(0)       // Global progress
const history = ref([])
const results = ref({}) // Session results container
const backtestStatus = ref('')  // Current backtest status message
const toastMessage = ref('')  // Toast notification message
const toastType = ref('info')  // 'success', 'error', 'info', 'warning'
const showToast = ref(false)  // Show toast notification

// Helper Constants & Functions
const HIGH_VOLATILITY_SYMBOLS = ['XAUUSD', 'BTCUSD', 'ETHUSD']

const getTFMins = (tf) => {
  const map = {
    'M1': 1, 'M5': 5, 'M15': 15, 'M30': 30,
    'H1': 60, 'H4': 240, 'D1': 1440
  }
  return map[tf] || 0
}

const isBadSession = (symbol, session) => {
  if (!symbol || !session) return false
  if (session === 'ASIA' || session === 'ASIA_LONDON') {
     if (symbol.includes('XAU')) return true
     if ((symbol.includes('EUR') || symbol.includes('GBP')) && !symbol.includes('JPY')) return true
  }
  return false
}



// Toast Notification Helper (Enhanced)
const showToastNotification = (message, type = 'info', duration = 3000) => {
  // Map custom types to standard styles/icons if needed, or just pass valid types
  // valid types: info, success, warning, error, risk, security
  toastMessage.value = message
  toastType.value = type
  showToast.value = true
  
  // Longer duration for critical alerts
  const realDuration = (type === 'risk' || type === 'error') ? 6000 : duration
  
  setTimeout(() => {
    showToast.value = false
  }, realDuration)
}

const currentSessionId = ref(null)  // Current backtest session ID for logs

// Manual Trade Modal State
const showManualTradeModal = ref(false)
const manualTradeForm = ref({
  symbol: 'XAUUSD',
  orderType: 'BUY',
  volume: 0.01,
  stopLoss: 0,
  takeProfit: 0
})
const manualTradeLoading = ref(false)

// Trading Mode State
const tradingMode = ref('backtest')  // 'backtest' or 'live'
const accounts = ref([])
const selectedAccountId = ref(null)
const activeAccount = computed(() => accounts.value.find(a => a.id === selectedAccountId.value))



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

// Execute Manual Trade
const executeManualTrade = async () => {
  if (!activeAccount.value) {
    showToastNotification('Please select an account first', 'warning')
    return
  }
  
  manualTradeLoading.value = true
  
  try {
    // Get symbol with prefix/suffix from account
    const prefix = activeAccount.value?.symbol_prefix || ''
    const suffix = activeAccount.value?.symbol_suffix || ''
    let symbol = manualTradeForm.value.symbol
    if (prefix && !symbol.startsWith(prefix)) {
      symbol = prefix + symbol
    }
    if (suffix && !symbol.endsWith(suffix)) {
      symbol = symbol + suffix
    }
    
    const payload = {
      account_id: activeAccount.value.id,
      symbol: symbol,
      order_type: manualTradeForm.value.orderType,
      volume: manualTradeForm.value.volume,
      stop_loss: manualTradeForm.value.stopLoss || null,
      take_profit: manualTradeForm.value.takeProfit || null
    }
    
    console.log('🎯 Executing manual trade:', payload)
    
    const response = await axios.post(`${API_URL}/api/trading/manual-order`, payload)
    
    if (response.data.success) {
      showToastNotification(`✅ Trade executed! Ticket: ${response.data.ticket}`, 'success')
      showManualTradeModal.value = false
      // Reload positions to see the new trade
      await loadOpenPositions()
    } else {
      showToastNotification(`❌ Trade failed: ${response.data.error}`, 'error')
    }
  } catch (error) {
    console.error('Manual trade error:', error)
    showToastNotification(`❌ Error: ${error.response?.data?.detail || error.message}`, 'error')
  } finally {
    manualTradeLoading.value = false
  }
}
// SYMBOL PRESETS - Complete configurations per symbol (based on research)
// SYMBOL PRESETS - Moved to src/constants/presets.js
const symbolPresets = SYMBOL_PRESETS



// Apply preset when symbol changes (v3.0: includes MACD + session)
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
    slot.direction = preset.direction
    if (preset.zigzag_lookback) slot.zigzag_lookback = preset.zigzag_lookback
    
    // v3.0: MACD & Session Killzone support
    if (preset.macd_fast) slot.macd_fast = preset.macd_fast
    if (preset.macd_slow) slot.macd_slow = preset.macd_slow
    if (preset.macd_signal) slot.macd_signal = preset.macd_signal
    if (preset.session_mode) slot.session_mode = preset.session_mode
    
    // Save & Notify
    if (typeof saveSlot === 'function') saveSlot(slot)
    if (typeof showToastNotification === 'function') showToastNotification('Auto-configured ' + slot.symbol + ' (v3.0)', 'info', 2000)
  }
}

// MULTI-SYMBOL SLOTS - Optimized for stability (M15 + H1 Conf + Wide Stops + NO Partial TP)


// Portfolio Synergy Settings
const portfolioSynergy = ref({
  max_risk: 4.0,  // Max combined risk across all slots
  max_positions: 2  // Max positions per symbol
})

// Computed: Enabled symbols for correlation matrix
const enabledSymbols = computed(() => {
  return slots.value.filter(s => s.enabled).map(s => s.symbol)
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


const trades = ref([])



// COMPOSABLES INITIALIZATION

// 1. Slot Management (Initialize first as other composables depend on `slots`)
const { 
  slots, 
  addSlot, 
  cloneSlot, 
  deleteSlot, 
  applySymbolPreset, 
  saveSlot, 
  loadSlots 
} = useSlotManager(API_URL, showToastNotification)

const { killSwitchActive, riskStatus, toggleKillSwitch } = useRiskManagement(API_URL, showToastNotification)

const { 
    portfolioMetrics, 
    totalActiveRisk, 
    totalPotentialRisk, 
    openPositionCount 
} = usePortfolioMetrics(slots)

// High-volatility symbol detection


// Methods
const runBacktest = async () => {
  // Get enabled slots
  const enabledSlots = slots.value.filter(s => s.enabled)
  console.log(`🔍 Total slots: ${slots.value.length}, Enabled slots: ${enabledSlots.length}`)
  if (enabledSlots.length === 0) {
    showToastNotification('Please enable at least one slot', 'warning')
    console.error('❌ No enabled slots found!')
    return
  }

  // Check if live mode requires active account
  if (tradingMode.value === 'live' && !activeAccount.value) {
    showToastNotification('Please select an account to start live trading', 'warning')
    return
  }

  isRunning.value = true
  backtestStatus.value = 'Initializing...'
  showToastNotification(`Starting ${tradingMode.value} mode for ${enabledSlots.length} slot(s)`, 'info')
  
  // Reset all enabled slots
  enabledSlots.forEach(slot => {
    slot.isRunning = true
    slot.progress = 0
    slot.results = {}
    slot.trades = []
  })
  
  // Also reset legacy state
  trades.value = []
  

  try {
    // Ensure socket is connected
    await ensureSocketConnected()
    
    
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
          volume_mode: slot.volume_mode || 'RISK',
          fixed_volume: slot.fixed_volume || 0.1,
          tp_ratio: slot.tp_ratio,
          sl_atr_multiplier: slot.sl_atr_multiplier,
          tsl_mode: slot.tsl_mode,
          timeframe: slot.timeframe,
          max_trade_duration_hours: slot.max_duration || 2,
          min_confluence_score: 5,
          account_id: activeAccount.value?.id,
          
          // Institutional
          confirmation_timeframe: slot.confirmation_timeframe,
          trading_session: slot.trading_session,
          session_end_action: slot.session_end_action,
          use_daily_bias: slot.use_daily_bias
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
      backtestStatus.value = 'Sending requests...'

      const promises = enabledSlots.map(async (slot) => {
        // Merge shared config with slot-specific overrides
        const payload = {
          // Symbol and direction from slot
          symbol: slot.symbol,
          direction_filter: slot.direction,
          // Slot-specific settings (override shared)
          risk_percent: slot.risk_percent,
          volume_mode: slot.volume_mode || 'RISK',
          fixed_volume: slot.fixed_volume || 0.1,
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
          confirmation_timeframe: slot.confirmation_timeframe,  // From Slot (Institutional)
          trading_session: slot.trading_session || 'ALL',
          session_end_action: slot.session_end_action || 'HOLD',
          use_daily_bias: slot.use_daily_bias,
          
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
          max_trade_duration_hours: slot.max_duration !== undefined ? slot.max_duration : 0, // Allow 0
          min_confluence_score: slot.min_confluence || 5,
          start_date: new Date(sharedConfig.value.start_date).toISOString(),
          end_date: new Date(sharedConfig.value.end_date).toISOString(),
          
          // Engine Configuration
          engine_type: slot.engine_type || 'ADAPTIVE',
          engine_config: slot.engine_type === 'GOLDEN' ? {
              structure: {
                  zigzag_lookback: slot.zigzag_lookback || 5
              },
              risk: {
                  risk_percent: slot.risk_percent,
                  atr_sl_multiplier: slot.sl_atr_multiplier,
                  tp1_ratio: slot.tp_ratio,
                  enable_trailing_stop: slot.tsl_mode !== 'OFF'
              }
          } : slot.engine_type === 'XAU_PRO' ? {
              // XAU_PRO (InstitutionalGoldEngine) Configuration
              structure: {
                  zigzag_lookback: slot.zigzag_lookback || 12
              },
              session_mode: slot.session_mode || 'BOTH_KZ',
              // SMC v4.0 Settings
              enable_order_blocks: slot.enable_order_blocks !== undefined ? slot.enable_order_blocks : true,
              ob_lookback: slot.ob_lookback || 20,
              enable_liquidity_sweep: slot.enable_liquidity_sweep !== undefined ? slot.enable_liquidity_sweep : true,
              sweep_lookback: slot.sweep_lookback || 10,
              enable_fvg: slot.enable_fvg !== undefined ? slot.enable_fvg : true,
              fvg_min_size_atr: slot.fvg_min_size_atr || 0.5,
              // RSI thresholds
              rsi_buy_threshold: slot.rsi_oversold || 40,
              rsi_sell_threshold: slot.rsi_overbought || 60
          } : {}
        }
        
        console.log(`📤 Sending backtest request for ${slot.symbol}...`, payload)
        const response = await axios.post(`${API_URL}/api/backtest/run`, payload)
        console.log(`✅ Backtest response for ${slot.symbol}:`, response.data)
        slot.sessionId = response.data.session_id
        return response
      })
      
      await Promise.all(promises)
      console.log(`🎉 All backtest requests sent successfully!`)
      backtestStatus.value = 'Running backtest...'
      showToastNotification(`Backtest started for ${enabledSlots.length} slot(s)`, 'success')
    }

  } catch (error) {
    console.error('❌ Trading failed:', error)
    console.error('Error details:', error.response?.data || error.message)
    showToastNotification('Failed to start: ' + (error.response?.data?.detail || error.message), 'error', 5000)
    isRunning.value = false
    backtestStatus.value = ''
    enabledSlots.forEach(slot => slot.isRunning = false)
  }
}

// Initialize Socket Trading Composable
const { ensureSocketConnected, setupSocketListeners, cleanupSocketListeners } = useSocketTrading(
  slots,
  sharedConfig,
  trades,
  isRunning,
  backtestStatus,
  killSwitchActive,
  riskStatus,
  tradingMode,
  showToastNotification,
  fetchHistory
)




const fetchHistory = async () => {
  try {
    const response = await axios.get('/api/backtest/history')
    history.value = response.data
  } catch (error) {
    console.error('Error fetching history:', error)
  }
}

// ==================== SLOT CRUD METHODS ====================




const loadSession = async (sessionId) => {
  try {
    const response = await axios.get(`/api/backtest/${sessionId}`)
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


// Lifecycle
onMounted(async () => {
  // Initial data load
  fetchHistory()
  fetchAccounts()
  await loadSlots()
  
  // Socket setup
  setupSocketListeners()
  await loadOpenPositions()
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
    // Basic alert or toast - showToastNotification is better if available
    if (typeof showToastNotification === 'function') {
        showToastNotification('No trades to export', 'warning')
    } else {
        alert('No trades to export.')
    }
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
    cleanupSocketListeners()
})
</script>
