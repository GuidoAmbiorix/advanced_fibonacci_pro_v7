<template>
  <div class="space-y-6">
    <div class="flex items-center justify-between">
      <h2 class="text-2xl font-bold text-primary">Settings & Configuration</h2>
      <div class="flex items-center space-x-4">
        <select v-model="currentBotId" @change="loadSettings" class="bg-white border border-slate-200 text-sm rounded px-3 py-2 outline-none focus:border-accent">
          <option v-for="bot in availableBots" :key="bot.id" :value="bot.id">
            {{ bot.name }} ({{ bot.symbol }})
          </option>
        </select>
        <button type="button" @click.prevent="createNewBot" class="px-3 py-2 bg-slate-200 text-slate-700 rounded hover:bg-slate-300 transition-colors text-sm font-medium">
          ➕ New Bot
        </button>
        <button type="button" @click.prevent="saveSettings" class="px-4 py-2 bg-accent text-white rounded hover:bg-accent/90 transition-colors">
          Save Changes
        </button>
      </div>
    </div>

    <!-- Tabs -->
    <div class="flex space-x-4 border-b border-slate-200">
      <button 
        v-for="tab in tabs" 
        :key="tab.id"
        @click="currentTab = tab.id"
        class="px-4 py-2 text-sm font-medium transition-colors border-b-2"
        :class="currentTab === tab.id ? 'border-accent text-accent' : 'border-transparent text-slate-500 hover:text-slate-700'"
      >
        {{ tab.label }}
      </button>
    </div>

    <!-- Content -->
    <div class="bg-white rounded-lg shadow-card p-6">
      
      <!-- General Settings -->
      <div v-if="currentTab === 'general'" class="space-y-6">
        
        <!-- System Configuration (Read-Only) -->
        <div class="bg-blue-50 p-5 rounded-lg border border-blue-200">
             <h4 class="font-bold text-blue-800 flex items-center mb-4">
                <span class="mr-2">🖥️</span> System Configuration (Environment)
            </h4>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                 <div>
                    <label class="block text-xs font-bold text-blue-700 uppercase mb-1">Account Type</label>
                    <div class="text-sm font-mono bg-white px-3 py-2 rounded border border-blue-100">{{ systemInfo.account_type || 'N/A' }}</div>
                </div>
                 <div>
                    <label class="block text-xs font-bold text-blue-700 uppercase mb-1">Role</label>
                    <div class="text-sm font-mono bg-white px-3 py-2 rounded border border-blue-100">{{ systemInfo.instance_role || 'N/A' }}</div>
                </div>
                 <div>
                    <label class="block text-xs font-bold text-blue-700 uppercase mb-1">Max Drawdown</label>
                    <div class="text-sm font-mono bg-white px-3 py-2 rounded border border-blue-100">{{ systemInfo.max_drawdown }}%</div>
                </div>
                <div>
                    <label class="block text-xs font-bold text-blue-700 uppercase mb-1">Suffix</label>
                    <div class="text-sm font-mono bg-white px-3 py-2 rounded border border-blue-100">{{ systemInfo.symbol_suffix || 'None' }}</div>
                </div>
            </div>
        </div>

        <h3 class="text-lg font-semibold text-slate-700">General Bot Configuration</h3>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div class="space-y-2">
            <label class="text-sm font-medium text-slate-600">Default Symbol</label>
            <input type="text" v-model="config.symbol" class="w-full p-2 border rounded focus:ring-2 focus:ring-accent/20 outline-none">
          </div>
          <div class="space-y-2">
            <label class="text-sm font-medium text-slate-600">Timeframe</label>
            <select v-model="config.timeframe" class="w-full p-2 border rounded focus:ring-2 focus:ring-accent/20 outline-none">
              <option value="M1">M1</option>
              <option value="M5">M5</option>
              <option value="M15">M15</option>
              <option value="H1">H1</option>
              <option value="H4">H4</option>
            </select>
          </div>
          <div class="space-y-2">
            <label class="text-sm font-medium text-slate-600">Base Risk %</label>
            <input type="number" step="0.1" v-model="config.risk_percent" class="w-full p-2 border rounded focus:ring-2 focus:ring-accent/20 outline-none">
          </div>
          <div class="space-y-2">
            <label class="text-sm font-medium text-slate-600">Max Trades</label>
            <input type="number" v-model="config.max_trades" class="w-full p-2 border rounded focus:ring-2 focus:ring-accent/20 outline-none">
          </div>
        </div>
      </div>

      <!-- Accounts Settings -->
      <div v-if="currentTab === 'accounts'" class="space-y-6">
        <AccountManager :botId="currentBotId" />
      </div>

      <!-- Strategy Settings -->
      <div v-if="currentTab === 'strategy'" class="space-y-6">
        <h3 class="text-lg font-semibold text-slate-700">Strategy Configuration</h3>
        
        <!-- Engine Selection -->
        <div class="bg-white p-4 rounded-lg border border-slate-200 shadow-sm mb-6">
            <h4 class="font-bold text-lg text-slate-800 mb-4">Trading Engine ⚙️</h4>
            <div class="flex space-x-4">
                <button 
                  @click="config.engine_type = 'ADAPTIVE'"
                  class="flex-1 py-3 px-4 rounded-lg border-2 transition-all flex items-center justify-center space-x-2"
                  :class="config.engine_type !== 'GOLDEN' ? 'border-blue-500 bg-blue-50 text-blue-700' : 'border-slate-200 hover:border-slate-300 text-slate-500'"
                >
                  <span class="text-xl">🛡️</span>
                  <div class="text-left">
                    <div class="font-bold">Adaptive (Legacy)</div>
                    <div class="text-xs opacity-75">Multi-Strategy (RSI, Stoch, VWAP)</div>
                  </div>
                </button>
                
                <button 
                  @click="config.engine_type = 'GOLDEN'"
                  class="flex-1 py-3 px-4 rounded-lg border-2 transition-all flex items-center justify-center space-x-2"
                  :class="config.engine_type === 'GOLDEN' ? 'border-amber-400 bg-amber-50 text-amber-800' : 'border-slate-200 hover:border-slate-300 text-slate-500'"
                >
                  <span class="text-xl">🏆</span>
                  <div class="text-left">
                    <div class="font-bold">Golden Engine</div>
                    <div class="text-xs opacity-75">Structure + Fib + Institutional</div>
                  </div>
                </button>
            </div>
        </div>

        <!-- GOLDEN ENGINE CONFIG -->
        <div v-if="config.engine_type === 'GOLDEN'" class="space-y-6 animate-fadeIn">
            <!-- Structure Settings -->
            <div class="bg-amber-50 p-5 rounded-lg border border-amber-200">
                <h4 class="font-bold text-amber-800 flex items-center mb-4">
                    <span class="mr-2">🌊</span> Market Structure & Waves
                </h4>
                <div class="grid grid-cols-2 gap-4">
                    <div>
                        <label class="block text-xs font-bold text-amber-700 uppercase mb-1">ZigZag Lookback</label>
                        <input type="number" v-model.number="config.engine_config.structure.zigzag_lookback" class="w-full bg-white border border-amber-200 rounded px-3 py-2 text-sm focus:border-amber-400 outline-none">
                        <p class="text-xs text-amber-600 mt-1">Bars to look back for pivots (Default: 5)</p>
                    </div>
                </div>
            </div>

            <!-- Risk Settings (Specific to Golden) -->
            <div class="bg-amber-50 p-5 rounded-lg border border-amber-200">
                <h4 class="font-bold text-amber-800 flex items-center mb-4">
                    <span class="mr-2">💰</span> Golden Risk Management
                </h4>
                <div class="grid grid-cols-2 gap-4">
                     <div>
                        <label class="block text-xs font-bold text-amber-700 uppercase mb-1">Risk % Per Trade</label>
                        <input type="number" v-model.number="config.risk_percent" step="0.1" class="w-full bg-white border border-amber-200 rounded px-3 py-2 text-sm focus:border-amber-400 outline-none">
                    </div>
                    <div>
                        <label class="block text-xs font-bold text-amber-700 uppercase mb-1">ATR SL Multiplier</label>
                        <input type="number" v-model.number="config.sl_atr_multiplier" step="0.1" class="w-full bg-white border border-amber-200 rounded px-3 py-2 text-sm focus:border-amber-400 outline-none">
                    </div>
                    <div>
                        <label class="block text-xs font-bold text-amber-700 uppercase mb-1">Tier 1 Profit (R)</label>
                        <input type="number" v-model.number="config.tp_ratio" step="0.1" class="w-full bg-white border border-amber-200 rounded px-3 py-2 text-sm focus:border-amber-400 outline-none">
                        <p class="text-xs text-amber-600 mt-1">Take 50% profit at this R-multiple</p>
                    </div>
                     <div>
                        <label class="block text-xs font-bold text-amber-700 uppercase mb-1">Runner Trailing</label>
                         <div class="flex items-center space-x-2 mt-2">
                             <input type="checkbox" v-model="config.enable_trailing_stop" class="form-checkbox text-amber-600 rounded">
                             <span class="text-sm text-amber-800">Enable ATR Trailing for Runner</span>
                         </div>
                    </div>
                </div>
            </div>

             <!-- Confluence Settings -->
            <div class="bg-amber-50 p-5 rounded-lg border border-amber-200">
                <h4 class="font-bold text-amber-800 flex items-center mb-4">
                    <span class="mr-2">✨</span> Confirmation
                </h4>
                <div class="space-y-3">
                     <label class="flex items-center space-x-2">
                         <input type="checkbox" checked disabled class="form-checkbox text-amber-600 rounded opacity-50">
                         <span class="text-sm text-amber-800">High Relative Volume (Auto-Enabled)</span>
                     </label>
                     <label class="flex items-center space-x-2">
                         <input type="checkbox" checked disabled class="form-checkbox text-amber-600 rounded opacity-50">
                         <span class="text-sm text-amber-800">RSI Non-Extreme (Auto-Enabled)</span>
                     </label>
                </div>
            </div>

        </div>

        <!-- Strategy Selection (LEGACY) -->
        <div v-else class="bg-slate-50 p-4 rounded-lg border border-slate-200 space-y-4">
            <h4 class="font-medium text-slate-700 mb-2">Active Strategies (Legacy)</h4>
            
            <label class="flex items-center space-x-3 cursor-pointer p-2 hover:bg-slate-100 rounded transition-colors">
                <input type="checkbox" v-model="config.use_adx_filter" class="form-checkbox h-5 w-5 text-blue-600 bg-white border-slate-300 rounded focus:ring-blue-500">
                <div>
                    <span class="text-sm font-medium text-slate-700 block">Use ADX Filter (>25)</span>
                    <span class="text-xs text-slate-500">Only trade when trend is strong</span>
                </div>
            </label>

            <div class="border-t border-slate-200 my-2"></div>

            <label class="flex items-center space-x-3 cursor-pointer p-2 hover:bg-slate-100 rounded transition-colors">
                <input type="checkbox" v-model="config.enable_vwap_strategy" class="form-checkbox h-5 w-5 text-purple-600 bg-white border-slate-300 rounded focus:ring-purple-500">
                <span class="text-sm font-medium text-slate-700">Enable VWAP Scalp</span>
            </label>

            <label class="flex items-center space-x-3 cursor-pointer p-2 hover:bg-slate-100 rounded transition-colors">
                <input type="checkbox" v-model="config.enable_stoch_strategy" class="form-checkbox h-5 w-5 text-purple-600 bg-white border-slate-300 rounded focus:ring-purple-500">
                <span class="text-sm font-medium text-slate-700">Enable Stoch Momentum</span>
            </label>

            <label class="flex items-center space-x-3 cursor-pointer p-2 hover:bg-slate-100 rounded transition-colors">
                <input type="checkbox" v-model="config.enable_institutional_strategy" class="form-checkbox h-5 w-5 text-yellow-500 bg-white border-slate-300 rounded focus:ring-yellow-500">
                <div>
                    <span class="text-sm font-bold text-yellow-600 block">Enable Institutional Sweep 💎</span>
                    <span class="text-xs text-slate-500">High probability liquidity sweeps (Score 9.8)</span>
                </div>
            </label>

            <label class="flex items-center space-x-3 cursor-pointer p-2 hover:bg-slate-100 rounded transition-colors">
                <input type="checkbox" v-model="config.enable_fibonacci_strategy" class="form-checkbox h-5 w-5 text-green-500 bg-white border-slate-300 rounded focus:ring-green-500">
                <div>
                    <span class="text-sm font-medium text-green-600 block">Enable Fibonacci Scalp 📐</span>
                    <span class="text-xs text-slate-500">Golden Zone (50-61.8%) retracements (Score 8.5)</span>
                </div>
            </label>
        </div>

        <!-- RSI Settings -->
        <div class="bg-slate-50 p-4 rounded-lg border border-slate-200 space-y-4">
            <h4 class="font-medium text-slate-700 mb-2">RSI Configuration 📉</h4>
            <div class="grid grid-cols-3 gap-4">
                <div>
                    <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Period</label>
                    <input type="number" v-model.number="config.rsi_period" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
                <div>
                    <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Overbought</label>
                    <input type="number" v-model.number="config.rsi_overbought" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
                <div>
                    <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Oversold</label>
                    <input type="number" v-model.number="config.rsi_oversold" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
            </div>
        </div>

        <!-- Signal Quality -->
        <div class="bg-slate-50 p-4 rounded-lg border border-slate-200">
            <h4 class="font-medium text-slate-700 mb-4">Signal Quality Filter</h4>
            
            <div class="space-y-4">
                <div>
                    <div class="flex justify-between mb-2">
                        <label class="text-sm font-medium text-slate-600">Min Confluence Score: <span class="text-accent font-bold">{{ config.min_confluence_score }}</span></label>
                    </div>
                    <input type="range" v-model.number="config.min_confluence_score" min="3" max="10" step="1" class="w-full h-2 bg-slate-200 rounded-lg appearance-none cursor-pointer accent-accent">
                    <div class="flex justify-between text-xs text-slate-400 mt-1">
                        <span>3 (All)</span>
                        <span>7 (Medium)</span>
                        <span>10 (Elite)</span>
                    </div>
                </div>

                <div class="p-3 bg-blue-50 border border-blue-100 rounded text-sm text-blue-800">
                    <p class="font-bold mb-1">Score Guide:</p>
                    <ul class="list-disc pl-4 space-y-1 text-xs">
                        <li><strong>7+</strong>: Range + VWAP + Stoch + Fib + Institutional</li>
                        <li><strong>8+</strong>: Fibonacci (8.5) + Institutional (9.8) ⭐ <span class="text-blue-600 font-bold">(Recommended)</span></li>
                        <li><strong>9+</strong>: Only Institutional Sweep (9.8)</li>
                    </ul>
                </div>
            </div>
        </div>
      </div>
      <div v-if="currentTab === 'risk'" class="space-y-6">
        <h3 class="text-lg font-semibold text-slate-700">Trade Management</h3>
        
        <!-- Trailing Stop Loss -->
        <div class="bg-slate-50 p-4 rounded-lg border border-slate-200">
          <div class="flex items-center justify-between mb-4">
            <label class="font-medium text-slate-700">Trailing Stop Loss</label>
            <label class="relative inline-flex items-center cursor-pointer">
              <input type="checkbox" v-model="config.trailing_sl" class="sr-only peer">
              <div class="w-11 h-6 bg-slate-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-accent/20 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-accent"></div>
            </label>
          </div>
          
          <div v-if="config.trailing_sl" class="grid grid-cols-1 md:grid-cols-2 gap-4 animate-fadeIn">
             <div>
               <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Mode</label>
               <select v-model="config.tsl_mode" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                 <option value="FIXED">Fixed Distance</option>
                 <option value="ATR">ATR Dynamic</option>
                 <option value="CHANDELIER">Chandelier Exit 📈</option>
                 <option value="TIERED">Tiered Profit Protection</option>
                 <option value="SWING">Swing-Based</option>
                 <option value="PSAR">Parabolic SAR</option>
               </select>
             </div>
             <div>
               <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Activation (R)</label>
               <input type="number" v-model.number="config.tsl_activation_r" step="0.1" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
             </div>

             <div v-if="config.tsl_mode === 'FIXED'" class="contents">
                <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Step (R)</label>
                  <input type="number" v-model.number="config.trailing_step" step="0.1" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
                 <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Distance (R)</label>
                  <input type="number" v-model.number="config.trailing_distance" step="0.1" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
             </div>

             <div v-if="config.tsl_mode === 'ATR'" class="contents">
                <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">ATR Period</label>
                  <input type="number" v-model.number="config.tsl_atr_period" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
                 <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">ATR Multiplier</label>
                  <input type="number" v-model.number="config.tsl_atr_multiplier" step="0.1" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
             </div>

             <div v-if="config.tsl_mode === 'CHANDELIER'" class="contents">
                <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Chandelier Period</label>
                  <input type="number" v-model.number="config.tsl_chandelier_period" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
                 <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Multiplier</label>
                  <input type="number" v-model.number="config.tsl_chandelier_mult" step="0.1" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
             </div>

             <div v-if="config.tsl_mode === 'SWING'" class="contents">
                <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Swing Lookback</label>
                  <input type="number" v-model.number="config.tsl_swing_lookback" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
                 <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Buffer (ATR)</label>
                  <input type="number" v-model.number="config.tsl_swing_buffer_atr" step="0.1" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
             </div>

             <div v-if="config.tsl_mode === 'PSAR'" class="contents">
                <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Start / Increment</label>
                  <div class="flex space-x-2">
                      <input type="number" v-model.number="config.tsl_psar_af_start" step="0.01" placeholder="Start" class="w-1/2 bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                      <input type="number" v-model.number="config.tsl_psar_af_increment" step="0.01" placeholder="Inc" class="w-1/2 bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                  </div>
                </div>
                 <div>
                  <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Max AF</label>
                  <input type="number" v-model.number="config.tsl_psar_af_max" step="0.01" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
                </div>
             </div>
          </div>
        </div>

        <!-- Partial Take Profit -->
        <div class="bg-slate-50 p-4 rounded-lg border border-slate-200">
          <div class="flex items-center justify-between mb-4">
            <label class="font-medium text-slate-700">Partial Take Profit</label>
            <label class="relative inline-flex items-center cursor-pointer">
              <input type="checkbox" v-model="config.partial_tp_on" class="sr-only peer">
              <div class="w-11 h-6 bg-slate-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-accent/20 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-accent"></div>
            </label>
          </div>
          <div v-if="config.partial_tp_on">
             <label class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 block">Amount (0.1 - 1.0)</label>
             <input type="number" v-model.number="config.partial_tp_amount" step="0.1" max="1.0" class="w-full bg-white border border-slate-200 rounded px-3 py-2 text-sm focus:border-accent outline-none">
             <p class="text-xs text-slate-400 mt-1">Percentage of position to close (e.g., 0.5 = 50%)</p>
          </div>
        </div>

      </div>

      <!-- News Settings -->
      <div v-if="currentTab === 'news'" class="space-y-6">
        <h3 class="text-lg font-semibold text-slate-700">News Filter</h3>
        <div class="space-y-4">
          <div class="flex items-center justify-between p-4 bg-slate-50 rounded">
            <div>
              <p class="font-medium text-slate-700">Avoid High Impact News</p>
              <p class="text-sm text-slate-500">Pause trading 15 mins before/after Red Folder events</p>
            </div>
            <label class="relative inline-flex items-center cursor-pointer">
              <input type="checkbox" v-model="news.avoid_high_impact" class="sr-only peer">
              <div class="w-11 h-6 bg-slate-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-accent/20 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-accent"></div>
            </label>
          </div>
        </div>
      </div>

      <!-- Prop Firm Settings -->
      <div v-if="currentTab === 'prop'" class="space-y-6">
        <h3 class="text-lg font-semibold text-slate-700">Prop Firm Protection</h3>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div class="space-y-2">
            <label class="text-sm font-medium text-slate-600">Max Daily Loss (%)</label>
            <input type="number" step="0.1" v-model="prop.max_daily_loss" class="w-full p-2 border rounded focus:ring-2 focus:ring-accent/20 outline-none">
          </div>
          <div class="space-y-2">
            <label class="text-sm font-medium text-slate-600">Max Total Drawdown (%)</label>
            <input type="number" step="0.1" v-model="prop.max_total_dd" class="w-full p-2 border rounded focus:ring-2 focus:ring-accent/20 outline-none">
          </div>
        </div>
      </div>

    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'
import AccountManager from '../components/settings/AccountManager.vue'

const currentTab = ref('general')
const tabs = [
  { id: 'general', label: 'General' },
  { id: 'accounts', label: 'Accounts 👥' },
  { id: 'strategy', label: 'Strategy 🧠' },
  { id: 'risk', label: 'Risk Manager' },
  { id: 'news', label: 'News Filter' },
  { id: 'prop', label: 'Prop Firm' }
]

const config = ref({
  symbol: 'EURUSD',
  timeframe: 'H1',
  risk_percent: 2.0,
  max_trades: 3,
  trailing_sl: false,
  tsl_mode: 'FIXED',
  tsl_activation_r: 1.0,
  trailing_step: 0.5,
  trailing_distance: 1.0,
  tsl_atr_period: 14,
  tsl_atr_multiplier: 1.5,
  tsl_chandelier_period: 22,
  tsl_chandelier_mult: 3.0,
  tsl_swing_lookback: 10,
  tsl_swing_buffer_atr: 0.5,
  tsl_psar_af_start: 0.02,
  tsl_psar_af_increment: 0.02,
  tsl_psar_af_max: 0.20,
  partial_tp_on: false,
  partial_tp_amount: 0.5,
  // Strategy Defaults
  use_adx_filter: true,
  enable_vwap_strategy: true,
  enable_stoch_strategy: true,
  enable_institutional_strategy: true,
  enable_fibonacci_strategy: true,
  // RSI Defaults
  rsi_period: 14,
  rsi_overbought: 70,
  rsi_oversold: 30,
  min_confluence_score: 7,
  // Engine Config
  engine_type: 'ADAPTIVE',
  engine_config: {
      structure: {
          zigzag_lookback: 5
      },
      risk: {
          risk_percent: 1.0,  // Will act as override/sync
          atr_sl_multiplier: 1.5,
          tp1_ratio: 1.5
      }
  }
})

const risk = ref({})

const news = ref({
  avoid_high_impact: true
})

const prop = ref({
  max_daily_loss: 3.0,
  max_total_dd: 10.0
})

const systemInfo = ref({})

const currentBotId = ref(null)
const availableBots = ref([])

async function loadSettings() {
  try {
    // 1. Get Bots
    const bots = await api.getBots()
    availableBots.value = bots
    
    // 2. Load System Info
    try {
        const info = await api.getSystemInfo()
        systemInfo.value = info
    } catch (e) {
        console.warn("Failed to load system info", e)
    }

    if (bots && bots.length > 0) {
      // If currentBotId is not set (first load), use the first one
      if (!currentBotId.value) {
        currentBotId.value = bots[0].id
      }
      
      // 2. Load Config
      const botConfig = await api.getBotSettings(currentBotId.value)
      Object.assign(config.value, botConfig)
      
      // Ensure Golden Config structure exists (migration compatibility)
      if (!config.value.engine_config) config.value.engine_config = {}
      if (!config.value.engine_config.structure) config.value.engine_config.structure = { zigzag_lookback: 5 }
      if (!config.value.engine_config.risk) config.value.engine_config.risk = { risk_percent: config.value.risk_percent || 1.0, atr_sl_multiplier: 1.5, tp1_ratio: 1.5 }
      
      // 3. Load Risk Profile
      const riskProfile = await api.getRiskProfile(currentBotId.value)
      Object.assign(risk.value, riskProfile)
      
      // 4. Load Prop Settings
      if (riskProfile.max_daily_loss) prop.value.max_daily_loss = riskProfile.max_daily_loss
      if (riskProfile.max_total_dd) prop.value.max_total_dd = riskProfile.max_total_dd
      
    } else {
      console.warn("No bots found")
    }
  } catch (e) {
    console.error("Error loading settings", e)
  }
}

async function saveSettings() {
  if (!currentBotId.value) {
    alert("No bot selected to save settings for.")
    return
  }

  try {
    // Update Config
    await api.updateBotSettings(currentBotId.value, config.value)
    
    // Update Risk Profile
    const riskUpdate = {
      ...risk.value,
      max_daily_loss: prop.value.max_daily_loss,
      max_total_dd: prop.value.max_total_dd
    }
    await api.updateRiskProfile(currentBotId.value, riskUpdate)
    
    alert('Settings saved successfully!')
  } catch (e) {
    console.error("Error saving settings", e)
    alert('Failed to save settings.')
  }
}

async function createNewBot() {
  const symbol = prompt("Enter Symbol (e.g. EURUSD):", "EURUSD");
  if (!symbol) return;
  
  try {
    // Get user ID from local storage
    const userStr = localStorage.getItem('user');
    let userId = 1;
    if (userStr) {
        try {
            const u = JSON.parse(userStr);
            if (u.id) userId = u.id;
        } catch (e) {
            console.error("Invalid user in localstorage", e);
        }
    }
    
    const payload = {
      user_id: Number(userId),
      name: `${symbol.toUpperCase()} Bot`,
      symbol: symbol.toUpperCase(),
      symbol_type: 'forex',
      timeframe: 'H1'
    };
    
    console.log("Creating bot with payload:", payload);
    
    const newBot = await api.createBotConfig(payload);
    
    // Refresh list
    await loadSettings();
    currentBotId.value = newBot.id;
    // Load the new settings
    const botConfig = await api.getBotSettings(newBot.id);
    Object.assign(config.value, botConfig);
    
    alert(`Bot for ${symbol.toUpperCase()} created!`);
  } catch (e) {
    console.error("Error creating bot", e);
    const msg = e.response?.data?.detail || e.message || "Failed to create bot";
    alert(`Error creating bot: ${JSON.stringify(msg)}`);
  }
}

onMounted(() => {
  loadSettings()
})
</script>
