<template>
  <div class="p-6 space-y-6">
    <!-- Header -->
    <div class="flex justify-between items-center">
      <div>
        <h1 class="text-2xl font-bold text-white">Strategy Backtester</h1>
        <p class="text-gray-400">Test strategies with historical data before going live</p>
      </div>
      <div class="flex space-x-3">
        <button 
          @click="runBacktest" 
          :disabled="isRunning"
          class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium flex items-center transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <span v-if="isRunning" class="mr-2 animate-spin">⟳</span>
          {{ isRunning ? `Running (${progress}%)` : 'Run Backtest' }}
        </button>
      </div>
    </div>

    <!-- MULTI-SYMBOL SLOTS (PORTFOLIO BOT) -->
    <div class="bg-gray-800 rounded-xl border border-gray-700 p-4 mb-6">
      <div class="flex justify-between items-center mb-3">
        <h3 class="text-sm font-semibold text-gray-300">🎯 Portfolio Slots</h3>
        <div class="flex items-center space-x-3">
          <span class="text-xs text-gray-500">Max Risk: {{ portfolioSynergy.max_risk }}%</span>
          <span class="text-xs text-gray-500">|</span>
          <span class="text-xs text-gray-500">Max Pos/Symbol: {{ portfolioSynergy.max_positions }}</span>
        </div>
      </div>
      
      <!-- 4 Slot Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
        <div v-for="slot in slots" :key="slot.id" 
             class="bg-gray-900 rounded-lg border transition-all"
             :class="slot.enabled ? 'border-blue-500' : 'border-gray-700 opacity-60'">
          
          <!-- Slot Header -->
          <div class="p-3 flex justify-between items-center border-b border-gray-700">
            <label class="flex items-center space-x-2 cursor-pointer">
              <input type="checkbox" v-model="slot.enabled" class="form-checkbox h-4 w-4 text-blue-500 bg-gray-800 border-gray-600 rounded">
              <span class="text-sm font-semibold text-white">Slot {{ slot.id + 1 }}</span>
            </label>
            <button @click="slot.expanded = !slot.expanded" class="text-gray-400 hover:text-white text-xs">
              {{ slot.expanded ? '▲' : '▼' }}
            </button>
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


    <!-- Portfolio Settings (Shared: Dates + Balance) -->
    <div class="bg-gray-800 rounded-xl border border-gray-700 p-4 mb-6">
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

    <!-- Results Dashboard - Full Width -->
    <div class="space-y-4">
      
      <!-- PORTFOLIO COMBINED SUMMARY -->
      <div class="bg-gradient-to-r from-blue-900/40 to-purple-900/40 rounded-xl border border-blue-700 p-4">
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
import socket from '../services/socket'

// State
const isRunning = ref(false)  // Global running state (any slot running)
const history = ref([])

// SYMBOL PRESETS - Complete configurations per symbol (based on research)
const symbolPresets = {
  'GBPJPY': { 
    name: 'GBP/JPY', emoji: '😈', volatility: 'HIGH',
    timeframe: 'M5', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.5, 
    rsi_period: 9, rsi_overbought: 75, rsi_oversold: 25, min_confluence: 5, max_duration: 0,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BUY_ONLY',  // Carry trade: Buy GBP (5.25%) vs Sell JPY (0.25%)
    description: 'The Beast 🔥 Carry trade long - Strong GBP/JPY rate differential' 
  },
  'EURUSD': { 
    name: 'EUR/USD', emoji: '💶', volatility: 'LOW',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.0, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 5, max_duration: 0,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',  // Most liquid, ranges well both directions
    description: 'Most liquid - Tight stops, trade both directions' 
  },
  'XAUUSD': { 
    name: 'XAU/USD', emoji: '🥇', volatility: 'EXTREME',
    timeframe: 'M5', tsl_mode: 'TIERED',
    risk_percent: 0.5, tp_ratio: 1.5, sl_atr_multiplier: 2.0, 
    rsi_period: 9, rsi_overbought: 80, rsi_oversold: 20, min_confluence: 5, max_duration: 0,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BUY_ONLY',  // Safe haven + Fed rate cuts = Gold bullish
    description: 'Gold Safe Haven 🛡️ Buy only - Fed easing cycle' 
  },
  'USDJPY': { 
    name: 'USD/JPY', emoji: '🇯🇵', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.0, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 5, max_duration: 0,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BUY_ONLY',  // Carry trade: Buy USD (5.33%) vs Sell JPY (0.25%)
    description: 'Carry Trade 📈 Buy only - USD/JPY yield differential' 
  },
  'AUDJPY': { 
    name: 'AUD/JPY', emoji: '🦘', volatility: 'MEDIUM',
    timeframe: 'M15', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.5, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 5, max_duration: 0,
    enable_vwap: true, enable_stoch: false, enable_institutional: true, enable_fibonacci: true,
    direction: 'BUY_ONLY',  // Carry trade: Buy AUD (4.1%) vs Sell JPY (0.25%)
    description: 'Carry Trade 📈 Buy only - Positive AUD swap' 
  },
  'NZDJPY': { 
    name: 'NZD/JPY', emoji: '🥝', volatility: 'MEDIUM',
    timeframe: 'M15', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.5, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 5, max_duration: 0,
    enable_vwap: true, enable_stoch: false, enable_institutional: true, enable_fibonacci: true,
    direction: 'BUY_ONLY',  // Carry trade: Buy NZD (5.5%) vs Sell JPY (0.25%)
    description: 'Carry Trade 📈 Buy only - Positive NZD swap' 
  },
  'EURCHF': { 
    name: 'EUR/CHF', emoji: '🇨🇭', volatility: 'LOW',
    timeframe: 'M15', tsl_mode: 'OFF',
    risk_percent: 1.5, tp_ratio: 1.5, sl_atr_multiplier: 0.75, 
    rsi_period: 14, rsi_overbought: 65, rsi_oversold: 35, min_confluence: 5, max_duration: 0,
    enable_vwap: true, enable_stoch: true, enable_institutional: false, enable_fibonacci: true,
    direction: 'BOTH',  // Range trading pair, both directions work
    description: 'Range Trading ↔️ Both directions - Low volatility' 
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

// MULTI-SYMBOL SLOTS - All enabled with researched optimal configs
const slots = ref([
  { id: 0, symbol: 'GBPJPY', enabled: true, expanded: false, isRunning: false, progress: 0, results: {}, trades: [], sessionId: null,
    ...symbolPresets['GBPJPY'] },  // BUY_ONLY - Carry trade
  { id: 1, symbol: 'XAUUSD', enabled: true, expanded: false, isRunning: false, progress: 0, results: {}, trades: [], sessionId: null,
    ...symbolPresets['XAUUSD'] },  // BUY_ONLY - Safe haven
  { id: 2, symbol: 'USDJPY', enabled: true, expanded: false, isRunning: false, progress: 0, results: {}, trades: [], sessionId: null,
    ...symbolPresets['USDJPY'] },  // BUY_ONLY - Carry trade
  { id: 3, symbol: 'AUDJPY', enabled: true, expanded: false, isRunning: false, progress: 0, results: {}, trades: [], sessionId: null,
    ...symbolPresets['AUDJPY'] }   // BUY_ONLY - Carry trade
])

// Portfolio Synergy Settings
const portfolioSynergy = ref({
  max_risk: 4.0,  // Max combined risk across all slots
  max_positions: 2  // Max positions per symbol
})

// PORTFOLIO COMBINED METRICS (computed from all enabled slots)
const portfolioMetrics = computed(() => {
  const enabledSlots = slots.value.filter(s => s.enabled && s.results)
  
  // Sum up all metrics
  let totalNetProfit = 0
  let totalTrades = 0
  let totalWins = 0
  let totalGrossProfit = 0
  let totalGrossLoss = 0
  let maxDrawdown = 0
  
  enabledSlots.forEach(slot => {
    if (slot.results?.net_profit !== undefined) {
      totalNetProfit += slot.results.net_profit
    }
    if (slot.results?.total_trades) {
      totalTrades += slot.results.total_trades
      // Estimate wins from win rate
      totalWins += Math.round(slot.results.total_trades * (slot.results.win_rate || 0) / 100)
    }
    if (slot.results?.gross_profit) {
      totalGrossProfit += slot.results.gross_profit
    }
    if (slot.results?.gross_loss) {
      totalGrossLoss += Math.abs(slot.results.gross_loss)
    }
    if (slot.results?.max_drawdown && slot.results.max_drawdown > maxDrawdown) {
      maxDrawdown = slot.results.max_drawdown  // Take worst drawdown
    }
  })
  
  // Calculate combined metrics
  const winRate = totalTrades > 0 ? (totalWins / totalTrades * 100) : 0
  const profitFactor = totalGrossLoss > 0 ? (totalGrossProfit / totalGrossLoss) : 0
  
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
  initial_balance: 1000,
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
    // Connect socket if not connected
    if (!socket.connected) {
      socket.connect()
    }
    
    // Start backtests for all enabled slots in parallel
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
        use_adx_filter: false,
        rsi_period: 14,
        rsi_overbought: 70,
        rsi_oversold: 30,
        enable_trailing_stop: slot.tsl_mode !== 'OFF',
        tsl_activation_r: 0.0,
        partial_tp_on: true,
        partial_tp_amount: 1.0,
        max_trade_duration_hours: 0,
        min_confluence_score: 5,
        start_date: new Date(sharedConfig.value.start_date).toISOString(),
        end_date: new Date(sharedConfig.value.end_date).toISOString()
      }
      
      const response = await axios.post('http://localhost:8000/api/backtest/run', payload)
      slot.sessionId = response.data.session_id
      return response
    })
    
    await Promise.all(promises)
    
  } catch (error) {
    console.error('Backtest failed:', error)
    alert('Failed to start backtest: ' + error.message)
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
}

const fetchHistory = async () => {
  try {
    const response = await axios.get('http://localhost:8000/api/backtest/history')
    history.value = response.data
  } catch (error) {
    console.error('Error fetching history:', error)
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
  fetchHistory()
  setupSocketListeners()
})

onUnmounted(() => {
    socket.off('backtest_progress')
    socket.off('backtest_trade')
    socket.off('backtest_complete')
})
</script>
