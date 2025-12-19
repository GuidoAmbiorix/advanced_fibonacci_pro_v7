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

    <!-- Progress Bar -->
    <div v-if="isRunning" class="w-full bg-gray-700 rounded-full h-2.5 mb-6">
      <div class="bg-blue-600 h-2.5 rounded-full transition-all duration-300" :style="{ width: progress + '%' }"></div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Configuration Panel -->
      <div class="lg:col-span-1 space-y-6">
        <div class="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <h2 class="text-lg font-semibold text-white mb-4">Configuration</h2>
          
          <div class="space-y-4">
            <!-- Symbol -->
            <div>
              <label class="block text-sm font-medium text-gray-400 mb-1">Symbol</label>
              <select v-model="config.symbol" @change="onSymbolChange" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
                <!-- 10 Stable Forex Pairs (Lower Volatility) -->
                <option value="EURCHF">EUR/CHF - Most Stable</option>
                <option value="USDCHF">USD/CHF - Safe Haven</option>
                <option value="EURGBP">EUR/GBP - European Stable</option>
                <option value="AUDNZD">AUD/NZD - Pacific Low Vol</option>
                <option value="EURNZD">EUR/NZD - Moderate Stable</option>
                <option value="AUDCAD">AUD/CAD - Commodity Smooth</option>
                <option value="NZDCAD">NZD/CAD - Low Fakeouts</option>
                <option value="USDSGD">USD/SGD - Tight Control</option>
                <option value="USDHKD">USD/HKD - Pegged Micro</option>
                <option value="CADCHF">CAD/CHF - Calm Pair</option>
                <option value="XAUUSD">XAU/USD - Gold 🥇</option>
              </select>
              
              <!-- Gold Warning Banner -->
              <div v-if="config.symbol === 'XAUUSD'" class="mt-2 p-2 bg-yellow-900/30 rounded border border-yellow-600">
                <div class="flex items-center space-x-2">
                  <span class="text-lg">⚠️</span>
                  <div>
                    <p class="text-yellow-400 text-xs font-bold">Gold (High Volatility)</p>
                    <p class="text-yellow-500 text-[10px]">Risk auto-reduced to 0.5%. Wider spreads expected (30-50 pips).</p>
                  </div>
                </div>
              </div>
            </div>

            <!-- Timeframe -->
            <div>
              <label class="block text-sm font-medium text-gray-400 mb-1">Timeframe</label>
              <select v-model="config.timeframe" @change="onTimeframeChange" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
                <option value="M1">M1 (1 Minute) ⚡</option>
                <option value="M5">M5 (5 Minutes) ⚡</option>
                <option value="M15">M15 (15 Minutes)</option>
                <option value="H1">H1 (1 Hour)</option>
                <option value="H4">H4 (4 Hours)</option>
                <option value="D1">D1 (Daily)</option>
              </select>
            </div>

            <!-- Confirmation Timeframe (for M1/M5 scalping) -->
            <div v-if="['M1', 'M5', 'M15'].includes(config.timeframe)">
              <label class="block text-sm font-medium text-gray-400 mb-1">Confirmation TF</label>
              <select v-model="config.confirmation_timeframe" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-purple-500 focus:outline-none">
                <option :value="null">Auto ({{ getAutoHTF(config.timeframe) }})</option>
                <option value="M5" v-if="config.timeframe === 'M1'">M5</option>
                <option value="M15">M15</option>
                <option value="H1">H1</option>
                <option value="H4">H4</option>
              </select>
              <p class="text-xs text-gray-500 mt-1">Higher timeframe for trend confirmation</p>
            </div>

            <!-- Strategy Mode -->
            <div>
              <label class="block text-sm font-medium text-gray-400 mb-1">Strategy Mode</label>
              <div class="grid grid-cols-2 gap-2">
                <button 
                  @click="config.strategy_mode = 'SWING'"
                  :class="config.strategy_mode === 'SWING' ? 'bg-blue-600 border-blue-500 text-white' : 'bg-gray-900 border-gray-700 text-gray-400 hover:bg-gray-800'"
                  class="px-3 py-2 rounded-lg border text-sm font-medium transition-colors"
                >
                  Swing (H1+)
                </button>
                <button 
                  @click="config.strategy_mode = 'SCALP'"
                  :class="config.strategy_mode === 'SCALP' ? 'bg-purple-600 border-purple-500 text-white' : 'bg-gray-900 border-gray-700 text-gray-400 hover:bg-gray-800'"
                  class="px-3 py-2 rounded-lg border text-sm font-medium transition-colors"
                >
                  Scalp (M15)
                </button>
              </div>
            </div>

            <!-- Date Range -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-gray-400 mb-1">Start Date</label>
                <input type="date" v-model="config.start_date" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-400 mb-1">End Date</label>
                <input type="date" v-model="config.end_date" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
              </div>
            </div>

            <!-- Balance & Risk -->
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-gray-400 mb-1">Start Balance ($)</label>
                <input type="number" v-model.number="config.initial_balance" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-400 mb-1">Risk per Trade (%)</label>
                <input type="number" v-model.number="config.risk_percent" step="0.001" min="0.001" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-blue-500 focus:outline-none">
              </div>
            </div>
            
            <!-- Advanced Options -->
             <div class="pt-2 border-t border-gray-700">
                <label class="flex items-center space-x-2 cursor-pointer">
                  <input type="checkbox" v-model="config.use_adx_filter" class="form-checkbox h-4 w-4 text-blue-600 bg-gray-900 border-gray-700 rounded">
                  <span class="text-sm text-gray-300">Use ADX Filter (>25)</span>
                </label>
                <div v-if="config.strategy_mode === 'SCALP'" class="mt-2 space-y-2">
                    <label class="flex items-center space-x-2 cursor-pointer">
                        <input type="checkbox" v-model="config.enable_vwap_strategy" class="form-checkbox h-4 w-4 text-purple-600 bg-gray-900 border-gray-700 rounded">
                        <span class="text-sm text-gray-300">Enable VWAP Scalp</span>
                    </label>
                    <label class="flex items-center space-x-2 cursor-pointer">
                        <input type="checkbox" v-model="config.enable_stoch_strategy" class="form-checkbox h-4 w-4 text-purple-600 bg-gray-900 border-gray-700 rounded">
                        <span class="text-sm text-gray-300">Enable Stoch Momentum</span>
                    </label>
                    <label class="flex items-center space-x-2 cursor-pointer">
                        <input type="checkbox" v-model="config.enable_institutional_strategy" class="form-checkbox h-4 w-4 text-yellow-500 bg-gray-900 border-gray-700 rounded">
                        <span class="text-sm text-yellow-400 font-bold">Enable Institutional Sweep 💎</span>
                    </label>
                    <label class="flex items-center space-x-2 cursor-pointer">
                        <input type="checkbox" v-model="config.enable_fibonacci_strategy" class="form-checkbox h-4 w-4 text-green-500 bg-gray-900 border-gray-700 rounded">
                        <span class="text-sm text-green-400">Enable Fibonacci Scalp 📐</span>
                    </label>
                </div>
             </div>

             <!-- Trailing Stop Loss Settings -->
             <div class="pt-3 border-t border-gray-700">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">🎯 Trailing Stop Loss</h3>
                
                <label class="flex items-center space-x-2 cursor-pointer mb-3">
                  <input type="checkbox" v-model="config.enable_trailing_stop" class="form-checkbox h-4 w-4 text-green-600 bg-gray-900 border-gray-700 rounded">
                  <span class="text-sm text-gray-300">Enable Trailing Stop</span>
                </label>

                <div v-if="config.enable_trailing_stop" class="space-y-3">
                  <!-- TSL Mode -->
                  <div>
                    <label class="block text-sm font-medium text-gray-400 mb-1">TSL Mode</label>
                    <select v-model="config.tsl_mode" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-green-500 focus:outline-none text-sm">
                      <option value="FIXED">Fixed R-Distance</option>
                      <option value="ATR">ATR Dynamic</option>
                      <option value="CHANDELIER">Chandelier Exit 📈</option>
                      <option value="TIERED">Tiered Profit Protection</option>
                      <option value="SWING">Swing-Based</option>
                      <option value="PSAR">Parabolic SAR</option>
                    </select>
                    <p class="text-xs text-gray-500 mt-1">
                      {{ getTslModeDescription(config.tsl_mode) }}
                    </p>
                  </div>

                  <!-- TSL Activation R -->
                  <div>
                    <label class="block text-sm font-medium text-gray-400 mb-1">Activation (R-profit)</label>
                    <input type="number" v-model.number="config.tsl_activation_r" step="0.1" min="0" max="3" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-green-500 focus:outline-none text-sm">
                    <p class="text-xs text-gray-500 mt-1">0 = immediate, 1.0 = after 1R profit</p>
                  </div>
                </div>
             </div>
             
             <!-- Partial Take Profit -->
             <div class="pt-3 border-t border-gray-700">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">Partial Take Profit</h3>
                
                <label class="flex items-center space-x-2 cursor-pointer mb-3">
                  <input type="checkbox" v-model="config.partial_tp_on" class="form-checkbox h-4 w-4 text-purple-600 bg-gray-900 border-gray-700 rounded">
                  <span class="text-sm text-gray-300">Enable Partial TP</span>
                </label>

                <div v-if="config.partial_tp_on">
                   <label class="block text-sm font-medium text-gray-400 mb-1">Amount (0.1 - 1.0)</label>
                   <input type="number" v-model.number="config.partial_tp_amount" step="0.1" max="1.0" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-purple-500 focus:outline-none text-sm">
                   <p class="text-xs text-gray-500 mt-1">Percentage of position to close (e.g., 0.5 = 50%)</p>
                </div>
             </div>

             <!-- Scalping Speed Settings (Only show for SCALP mode) -->
             <div v-if="config.strategy_mode === 'SCALP'" class="pt-3 border-t border-gray-700 bg-purple-900/20 -mx-5 px-5 py-3 rounded-b-xl">
                <h3 class="text-sm font-semibold text-purple-300 mb-3">⚡ Scalping Speed Settings</h3>
                
                <div class="grid grid-cols-3 gap-3">
                  <!-- TP Ratio -->
                  <div>
                    <label class="text-xs font-bold text-gray-500 uppercase tracking-wider mb-1 block">TP Ratio</label>
                    <input type="number" v-model.number="config.tp_ratio" step="0.1" min="0.5" max="3" class="w-full bg-gray-900 border border-purple-600 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-purple-500 focus:outline-none text-sm">
                    <p class="text-[10px] text-gray-500 mt-1">1.0 = Fast TP</p>
                  </div>
                  <!-- SL ATR Mult -->
                  <div>
                    <label class="text-xs font-bold text-gray-500 uppercase tracking-wider mb-1 block">SL × ATR</label>
                    <input type="number" v-model.number="config.sl_atr_multiplier" step="0.1" min="0.5" max="3" class="w-full bg-gray-900 border border-purple-600 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-purple-500 focus:outline-none text-sm">
                    <p class="text-[10px] text-gray-500 mt-1">1.0 = Tight SL</p>
                  </div>
                  <!-- Max Duration -->
                  <div>
                    <label class="text-xs font-bold text-gray-500 uppercase tracking-wider mb-1 block">Max Hours</label>
                    <input type="number" v-model.number="config.max_trade_duration_hours" step="0.5" min="0" max="24" class="w-full bg-gray-900 border border-purple-600 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-purple-500 focus:outline-none text-sm">
                    <p class="text-[10px] text-gray-500 mt-1">0 = No limit</p>
                  </div>
                </div>
                <p class="text-xs text-purple-400 mt-2">💡 For fastest trades: TP 1.0, SL 1.0, Max 1h</p>
             </div>

             <!-- RSI Settings -->
             <div class="pt-3 border-t border-gray-700">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">📉 RSI Configuration</h3>
                <div class="grid grid-cols-3 gap-4">
                    <div>
                        <label class="text-xs font-bold text-gray-500 uppercase tracking-wider mb-1 block">Period</label>
                        <input type="number" v-model.number="config.rsi_period" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-purple-500 focus:outline-none text-sm">
                    </div>
                    <div>
                        <label class="text-xs font-bold text-gray-500 uppercase tracking-wider mb-1 block">Overbought</label>
                        <input type="number" v-model.number="config.rsi_overbought" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-purple-500 focus:outline-none text-sm">
                    </div>
                    <div>
                        <label class="text-xs font-bold text-gray-500 uppercase tracking-wider mb-1 block">Oversold</label>
                        <input type="number" v-model.number="config.rsi_oversold" class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-white focus:ring-2 focus:ring-purple-500 focus:outline-none text-sm">
                    </div>
                </div>
             </div>

             <!-- Signal Quality Settings -->
             <div class="pt-3 border-t border-gray-700">
                <h3 class="text-sm font-semibold text-gray-300 mb-3">📊 Signal Quality</h3>
                
                <div>
                  <label class="block text-sm font-medium text-gray-400 mb-1">
                    Min Confluence Score: <span class="text-white font-bold">{{ config.min_confluence_score }}</span>
                  </label>
                  <input 
                    type="range" 
                    v-model.number="config.min_confluence_score" 
                    min="3" 
                    max="10" 
                    step="1" 
                    class="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-blue-500"
                  >
                  <div class="flex justify-between text-xs text-gray-500 mt-1">
                    <span>3 (All)</span>
                    <span>7 (Medium)</span>
                    <span>10 (Elite)</span>
                  </div>
                  <p class="text-xs text-gray-500 mt-2">
                    {{ getConfluenceDescription(config.min_confluence_score) }}
                  </p>
                </div>
             </div>

          </div>
        </div>

        <!-- Recent History -->
        <div class="bg-gray-800 rounded-xl border border-gray-700 p-5">
          <h2 class="text-lg font-semibold text-white mb-4">Recent Tests</h2>
          <div class="space-y-3">
            <div v-if="history.length === 0" class="text-center text-gray-500 py-4">
              No recent backtests
            </div>
            <div 
              v-for="session in history" 
              :key="session.id"
              @click="loadSession(session.id)"
              class="p-3 bg-gray-900 rounded-lg border border-gray-700 hover:border-blue-500 cursor-pointer transition-colors"
            >
              <div class="flex justify-between items-start mb-1">
                <span class="font-medium text-white">{{ session.symbol }}</span>
                <span 
                  class="text-xs px-2 py-0.5 rounded"
                  :class="session.net_profit >= 0 ? 'bg-green-900 text-green-400' : 'bg-red-900 text-red-400'"
                >
                  {{ session.net_profit >= 0 ? '+' : '' }}${{ session.net_profit?.toFixed(2) }}
                </span>
              </div>
              <div class="flex justify-between text-xs text-gray-400">
                <span>{{ session.timeframe }} • {{ session.total_trades }} Trades</span>
                <span>PF: {{ session.profit_factor?.toFixed(2) }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Results Dashboard -->
      <div class="lg:col-span-2 space-y-6">
        <!-- Key Metrics -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div class="bg-gray-800 p-4 rounded-xl border border-gray-700">
            <div class="text-sm text-gray-400 mb-1">Net Profit</div>
            <div class="text-2xl font-bold" :class="results.net_profit >= 0 ? 'text-green-400' : 'text-red-400'">
              {{ results.net_profit ? (results.net_profit >= 0 ? '+' : '') + '$' + results.net_profit.toFixed(2) : '-' }}
            </div>
          </div>
          <div class="bg-gray-800 p-4 rounded-xl border border-gray-700">
            <div class="text-sm text-gray-400 mb-1">Win Rate</div>
            <div class="text-2xl font-bold text-white">
              {{ results.win_rate ? results.win_rate.toFixed(1) + '%' : '-' }}
            </div>
          </div>
          <div class="bg-gray-800 p-4 rounded-xl border border-gray-700">
            <div class="text-sm text-gray-400 mb-1">Profit Factor</div>
            <div class="text-2xl font-bold" :class="getPfColor(results.profit_factor)">
              {{ results.profit_factor ? results.profit_factor.toFixed(2) : '-' }}
            </div>
          </div>
          <div class="bg-gray-800 p-4 rounded-xl border border-gray-700">
            <div class="text-sm text-gray-400 mb-1">Max Drawdown</div>
            <div class="text-2xl font-bold text-red-400">
              {{ results.max_drawdown ? results.max_drawdown.toFixed(1) + '%' : '-' }}
            </div>
          </div>
        </div>

        <!-- Equity Curve Placeholder (Future Implementation) -->
        <div class="bg-gray-800 rounded-xl border border-gray-700 p-5 h-64 flex items-center justify-center">
            <div class="text-center">
                <p class="text-gray-500">Equity Curve Chart</p>
                <p class="text-xs text-gray-600">(Coming Soon)</p>
            </div>
        </div>

        <!-- Trade List -->
        <div class="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
          <div class="p-4 border-b border-gray-700">
            <h3 class="font-semibold text-white">Trade History</h3>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="bg-gray-900 text-gray-400">
                <tr>
                  <th class="px-3 py-3">Open Time</th>
                  <th class="px-3 py-3">Close Time</th>
                  <th class="px-3 py-3">Duration</th>
                  <th class="px-3 py-3">Type</th>
                  <th class="px-3 py-3">Entry</th>
                  <th class="px-3 py-3">Exit</th>
                  <th class="px-3 py-3">Profit</th>
                  <th class="px-3 py-3">Balance</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-700">
                <tr v-if="trades.length === 0">
                    <td colspan="8" class="px-4 py-8 text-center text-gray-500">No trades to display</td>
                </tr>
                <tr v-for="trade in trades" :key="trade.id" class="hover:bg-gray-750">
                  <td class="px-3 py-3 text-gray-400 text-xs">{{ formatDateTime(trade.entry_time) }}</td>
                  <td class="px-3 py-3 text-gray-400 text-xs">{{ formatDateTime(trade.exit_time) }}</td>
                  <td class="px-3 py-3 text-xs">
                    <span :class="getDurationColor(trade.entry_time, trade.exit_time)">
                      {{ formatDuration(trade.entry_time, trade.exit_time) }}
                    </span>
                  </td>
                  <td class="px-3 py-3">
                    <span 
                      class="px-2 py-0.5 rounded text-xs font-medium"
                      :class="trade.trade_type === 'BUY' ? 'bg-green-900 text-green-400' : 'bg-red-900 text-red-400'"
                    >
                      {{ trade.trade_type }}
                    </span>
                  </td>
                  <td class="px-3 py-3 text-gray-300 text-xs">{{ trade.entry_price?.toFixed(5) }}</td>
                  <td class="px-3 py-3 text-gray-300 text-xs">{{ trade.exit_price?.toFixed(5) }}</td>
                  <td class="px-3 py-3 font-medium text-sm" :class="trade.profit >= 0 ? 'text-green-400' : 'text-red-400'">
                    {{ trade.profit >= 0 ? '+' : '' }}${{ trade.profit?.toFixed(2) }}
                  </td>
                  <td class="px-3 py-3 text-gray-300">${{ trade.balance_after?.toFixed(2) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import axios from 'axios'
import socket from '../services/socket'

// State
const isRunning = ref(false)
const progress = ref(0)
const history = ref([])
const trades = ref([])
const results = ref({})

// Config - GOLD WINNING CONFIGURATION (+$7.1M, 63% WR)
const config = ref({
  symbol: 'XAUUSD',  // GOLD - winning symbol
  timeframe: 'M5',
  confirmation_timeframe: null,  // Auto (M15)
  strategy_mode: 'SCALP',
  start_date: '2024-10-01',
  end_date: '2024-10-04',  // 4 days like winning test
  initial_balance: 1000,
  risk_percent: 0.001,  // CRITICAL: 0.001% for Gold
  use_adx_filter: false,  // OFF for winning config
  enable_vwap_strategy: true,  // ON
  enable_stoch_strategy: true,  // ON
  enable_institutional_strategy: true,  // ON for Gold
  enable_fibonacci_strategy: true,  // ON for Gold
  // RSI Defaults
  rsi_period: 14,
  rsi_overbought: 70,
  rsi_oversold: 30,
  // Trailing Stop Loss - ATR mode for Gold (adapts to volatility)
  enable_trailing_stop: true,
  tsl_mode: 'ATR',  // ATR recommended for Gold scalping
  tsl_activation_r: 0.0,
  // Partial Take Profit - ON 100%
  partial_tp_on: true,
  partial_tp_amount: 1.0,  // 100% (winning config)
  // WINNING SCALPING SETTINGS
  tp_ratio: 2.0,  // 2.0R (winning)
  sl_atr_multiplier: 1.0,  // 1.0 ATR (winning)
  max_trade_duration_hours: 0,  // No limit (winning)
  // Signal Quality
  min_confluence_score: 5  // Lower for more signals
})

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
  isRunning.value = true
  trades.value = []
  results.value = {}
  
  try {
    // Convert dates to ISO strings
    const payload = {
      ...config.value,
      start_date: new Date(config.value.start_date).toISOString(),
      end_date: new Date(config.value.end_date).toISOString()
    }
    
    const response = await axios.post('http://localhost:8000/api/backtest/run', payload)
    const sessionId = response.data.session_id
    
    // Connect socket if not connected
    if (!socket.connected) {
        socket.connect()
    }
    
  } catch (error) {
    console.error('Backtest failed:', error)
    alert('Failed to start backtest')
    isRunning.value = false
  }
}

// Socket Event Listeners
const setupSocketListeners = () => {
    socket.on('backtest_progress', (data) => {
        progress.value = Math.round(data.progress)
        
        // Update live stats if available
        if (data.stats) {
            results.value = {
                ...results.value,
                net_profit: data.stats.balance - config.value.initial_balance,
                total_trades: data.stats.trades,
                // Calculate other metrics roughly or wait for completion
            }
        }
    })

    socket.on('backtest_trade', (data) => {
        const trade = data.trade
        if (trade.type === 'CLOSE') {
            // Add to trades list with full timing info
            trades.value.unshift({
                id: Date.now(), // Temp ID
                entry_time: trade.entry_time,  // From callback
                exit_time: trade.exit_time,    // From callback
                trade_type: trade.trade_type,
                entry_price: trade.entry_price,
                exit_price: trade.price,
                profit: trade.pnl,
                balance_after: trade.balance
            })
            
            // Update balance in results
            results.value.net_profit = trade.balance - config.value.initial_balance
        }
    })

    socket.on('backtest_complete', (data) => {
        isRunning.value = false
        progress.value = 100
        results.value = data.results
        fetchHistory()
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
