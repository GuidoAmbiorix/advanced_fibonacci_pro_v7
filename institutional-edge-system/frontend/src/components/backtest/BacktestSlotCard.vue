<template>
  <div class="group relative overflow-hidden rounded-xl border transition-all duration-300 hover:scale-[1.01]"
       :class="slot.isRunning
         ? 'bg-gradient-to-br from-blue-800/60 to-purple-900/60 border-blue-400/70 shadow-xl shadow-blue-500/30'
         : slot.enabled
           ? 'bg-gradient-to-br from-slate-800/80 to-slate-900/80 border-blue-500/50 shadow-lg shadow-blue-500/10'
           : 'bg-gray-900/50 border-gray-700/50 opacity-60'">

    <!-- Animated border for running slots -->
    <div v-if="slot.isRunning" class="absolute inset-0 pointer-events-none">
      <div class="absolute inset-0 bg-gradient-to-r from-blue-500/20 via-purple-500/20 to-blue-500/20 animate-pulse"></div>
    </div>

    <!-- Slot glow effect when enabled -->
    <div v-if="slot.enabled && !slot.isRunning" class="absolute inset-0 bg-gradient-to-br from-blue-500/5 to-purple-500/5 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none"></div>
    
    <!-- Slot Header -->
    <div class="relative z-10 p-3 flex justify-between items-center border-b border-gray-700/50">
      <label class="flex items-center space-x-2 cursor-pointer">
        <div class="relative">
          <input type="checkbox" v-model="slot.enabled" @change="$emit('save', slot)"
                 :disabled="slot.isRunning"
                 class="sr-only peer">
          <div class="w-5 h-5 rounded bg-gray-700 border border-gray-600 peer-checked:bg-gradient-to-r peer-checked:from-blue-600 peer-checked:to-cyan-500 peer-checked:border-transparent transition-all flex items-center justify-center"
               :class="slot.isRunning ? 'opacity-50 cursor-not-allowed' : ''">
            <svg v-if="slot.enabled" class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"></path>
            </svg>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-sm font-bold" :class="slot.enabled ? 'text-white' : 'text-gray-400'">
            Slot {{ slot.id + 1 }}
          </span>
          <!-- Running indicator -->
          <span v-if="slot.isRunning" class="flex items-center gap-1 px-1.5 py-0.5 bg-blue-500/20 rounded text-[10px] text-blue-300">
            <span class="animate-spin">⟳</span>
            Running
          </span>
        </div>
      </label>
      <div class="flex items-center space-x-1">
        <!-- Clone Button -->
        <button @click="$emit('clone', slot)"
                :disabled="slot.isRunning"
                class="p-1 rounded hover:bg-blue-500/20 text-blue-400 hover:text-blue-300 transition-colors disabled:opacity-30"
                title="Clone Slot Settings">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
          </svg>
        </button>
        <!-- Expand Button -->
        <button @click="slot.expanded = !slot.expanded"
                class="p-1 rounded hover:bg-gray-700/50 text-gray-400 hover:text-white transition-colors">
          <svg class="w-4 h-4 transition-transform" :class="slot.expanded ? 'rotate-180' : ''" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
          </svg>
        </button>
        <!-- Delete Button -->
        <button @click="$emit('delete', slot.id)"
                :disabled="slot.isRunning"
                class="p-1 rounded hover:bg-red-500/20 text-red-400 hover:text-red-300 transition-colors disabled:opacity-30"
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
              @change="$emit('preset', slot)"
              class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-sm disabled:opacity-50">
        <option v-for="(preset, sym) in presets" :key="sym" :value="sym">
          {{ preset.emoji }} {{ preset.name }}
        </option>
      </select>
      <!-- Symbol Info -->
      <div v-if="presets[slot.symbol]" class="text-[10px] text-gray-500 px-1">
        {{ presets[slot.symbol].description }}
        <span class="ml-1 px-1 rounded" 
              :class="presets[slot.symbol].volatility === 'EXTREME' ? 'bg-red-900 text-red-400' :
                      presets[slot.symbol].volatility === 'HIGH' ? 'bg-orange-900 text-orange-400' :
                      presets[slot.symbol].volatility === 'MEDIUM' ? 'bg-yellow-900 text-yellow-400' :
                      'bg-green-900 text-green-400'">
          {{ presets[slot.symbol].volatility }}
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
      
      <!-- Row 0: Engine Selection -->
      <div class="flex items-center justify-between bg-gray-800 p-2 rounded border border-gray-700">
         <span class="text-[10px] text-gray-400 font-medium uppercase tracking-wider">Engine</span>
          <div class="flex space-x-1">
             <button @click="slot.engine_type = 'XAU_PRO'" 
                     class="px-2 py-1 text-[10px] rounded transition-colors bg-gradient-to-r from-yellow-600 to-yellow-500 text-white font-bold shadow-lg shadow-yellow-500/20 cursor-default">
               🥇 Institutional Gold (XAU PRO)
             </button>
          </div>
      </div>

      <!-- Row 1: Timeframe + Confirmation + TSL -->
      <div class="grid grid-cols-3 gap-2">
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
          <label class="text-[10px] text-gray-500">Confirm TF</label>
          <select v-model="slot.confirmation_timeframe" class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs"
                  :class="{'border-red-500': getTFMins(slot.confirmation_timeframe) < getTFMins(slot.timeframe)}">
            <option :value="null">Auto</option>
            <option value="M5">M5</option>
            <option value="M15">M15</option>
            <option value="M30">M30</option>
            <option value="H1">H1</option>
            <option value="H4">H4</option>
            <option value="D1">D1</option>
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
      
      <!-- Institutional Session Control -->
      <div class="p-2 bg-blue-900/10 rounded border border-blue-500/20 space-y-2">
        <div class="flex justify-between items-center">
           <span class="text-[10px] font-bold text-blue-300 uppercase tracking-wider">🏛️ Institutional Control</span>
           <span v-if="isBadSession(slot.symbol, slot.trading_session)" class="text-[9px] text-yellow-400 font-medium px-1.5 py-0.5 bg-yellow-900/30 rounded border border-yellow-500/30">
              ⚠ Low Volatility Warning
           </span>
        </div>
        <div class="grid grid-cols-2 gap-2">
            <div>
               <label class="text-[10px] text-gray-500">Session Killzone v3.0</label>
               <select v-model="slot.session_mode" class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-[10px]">
                  <option value="BOTH_KZ">🎯 London + NY Killzones (Recommended)</option>
                  <option value="LONDON_KZ">🇬🇧 London Killzone (07-10 UTC)</option>
                  <option value="NY_KZ">🇺🇸 NY Killzone (12-15 UTC)</option>
                  <option value="OVERLAP_KZ">⚡ Overlap Only (13-16 UTC)</option>
                  <option value="ALL">🌍 All Sessions (Not Recommended)</option>
               </select>
            </div>
           <div>
              <label class="text-[10px] text-gray-500">Session End</label>
              <select v-model="slot.session_end_action" class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-[10px]">
                 <option value="HOLD">✋ Hold Trades</option>
                 <option value="CLOSE">❌ Close All</option>
                 <option value="DISABLE_NEW">⛔ No New Entries</option>
              </select>
           </div>
        </div>
        
        <!-- D1 Bias Toggle -->
        <div class="flex items-center space-x-2 pt-1 border-t border-blue-500/20 mt-1">
           <input type="checkbox" v-model="slot.use_daily_bias" :id="'bias-'+slot.id" 
                  class="w-3 h-3 rounded bg-gray-700 border-gray-600 text-blue-500 focus:ring-blue-500 focus:ring-offset-gray-900">
           <label :for="'bias-'+slot.id" class="text-[10px] text-gray-400 select-none cursor-pointer hover:text-blue-300 transition-colors">
              Filter Trades with Daily Trend (D1 Bias)
           </label>
        </div>
      </div>
      
      <!-- Row 2: Risk/TP/SL -->
      <div class="grid grid-cols-3 gap-2">
        <div>
          <div class="flex justify-between items-center mb-1">
             <label class="text-[10px] text-gray-500">Mode</label>
             <select v-model="slot.volume_mode" class="bg-gray-700 text-[10px] rounded px-1 text-blue-300 border-none h-4">
                <option value="RISK">Risk %</option>
                <option value="FIXED">Lots</option>
             </select>
          </div>
          <input v-if="slot.volume_mode === 'RISK' || !slot.volume_mode" 
                 type="number" v-model.number="slot.risk_percent" step="0.5" min="0.1" max="5" 
                 class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-xs"
                 title="Risk percentage per trade">
          <input v-else
                 type="number" v-model.number="slot.fixed_volume" step="0.01" min="0.01" max="50" 
                 class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-cyan-300 text-xs font-bold"
                 title="Fixed lot size">
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
      
      <!-- XAU PRO CONFIGURATION -->
      <div class="space-y-3 animate-in fade-in slide-in-from-top-1 duration-300">
         <!-- MACD Momentum -->
         <div class="p-2 bg-yellow-900/10 rounded border border-yellow-600/30">
            <div class="mb-2 flex items-center gap-2">
               <span class="text-[10px] font-bold text-yellow-400 uppercase tracking-wider">⚡ Momentum (MACD)</span>
            </div>
            <div class="grid grid-cols-3 gap-2">
               <div>
                  <label class="text-[10px] text-gray-400">Fast</label>
                  <input type="number" v-model.number="slot.config.macd_fast" placeholder="8"
                         class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-white text-xs">
               </div>
               <div>
                  <label class="text-[10px] text-gray-400">Slow</label>
                  <input type="number" v-model.number="slot.config.macd_slow" placeholder="21"
                         class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-white text-xs">
               </div>
               <div>
                  <label class="text-[10px] text-gray-400">Signal</label>
                  <input type="number" v-model.number="slot.config.macd_signal" placeholder="5"
                         class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-white text-xs">
               </div>
            </div>
         </div>

         <!-- RSI Value -->
         <div class="p-2 bg-purple-900/10 rounded border border-purple-600/30">
            <div class="mb-2 flex items-center gap-2">
               <span class="text-[10px] font-bold text-purple-400 uppercase tracking-wider">📊 Value (RSI)</span>
            </div>
            <div class="grid grid-cols-3 gap-2">
               <div>
                  <label class="text-[10px] text-gray-400">Period</label>
                  <input type="number" v-model.number="slot.config.rsi_period" placeholder="14"
                         class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-white text-xs">
               </div>
               <div>
                  <label class="text-[10px] text-gray-400">Buy Ceiling</label>
                  <input type="number" v-model.number="slot.config.rsi_buy_threshold" placeholder="45"
                         class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-green-200 text-xs">
               </div>
               <div>
                  <label class="text-[10px] text-gray-400">Sell Floor</label>
                  <input type="number" v-model.number="slot.config.rsi_sell_threshold" placeholder="55"
                         class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-red-200 text-xs">
               </div>
            </div>
         </div>
         
         <!-- Structure & Risk -->
         <div class="p-2 bg-blue-900/10 rounded border border-blue-500/20">
            <div class="mb-2 flex items-center gap-2">
               <span class="text-[10px] font-bold text-blue-400 uppercase tracking-wider">🛡️ Structure (v3.0)</span>
            </div>
            <div class="grid grid-cols-1 gap-2">
               <div>
                   <label class="text-[10px] text-gray-400">ZigZag Lookback (Recommended: 12)</label>
                   <input type="number" v-model.number="slot.zigzag_lookback" min="3" max="20" placeholder="12"
                          class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-white text-xs">
               </div>
            </div>
         </div>
         
         <!-- SMC v4.0 - Smart Money Concepts -->
         <div class="p-2 bg-purple-900/10 rounded border border-purple-500/20">
            <div class="mb-2 flex items-center gap-2">
               <span class="text-[10px] font-bold text-purple-400 uppercase tracking-wider">🧠 Smart Money (v4.0)</span>
            </div>
            <div class="grid grid-cols-2 gap-2">
               <!-- Order Blocks -->
               <div class="flex items-center gap-2">
                  <input type="checkbox" v-model="slot.enable_order_blocks" class="w-3 h-3 accent-purple-500">
                  <label class="text-[10px] text-gray-400">Order Blocks</label>
               </div>
               <div>
                  <label class="text-[10px] text-gray-400">OB Lookback</label>
                  <input type="number" v-model.number="slot.ob_lookback" min="5" max="50" placeholder="20"
                         class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-white text-xs">
               </div>
               
               <!-- Liquidity Sweep -->
               <div class="flex items-center gap-2">
                  <input type="checkbox" v-model="slot.enable_liquidity_sweep" class="w-3 h-3 accent-purple-500">
                  <label class="text-[10px] text-gray-400">Liquidity Sweep</label>
               </div>
               <div>
                  <label class="text-[10px] text-gray-400">Sweep Lookback</label>
                  <input type="number" v-model.number="slot.sweep_lookback" min="5" max="30" placeholder="10"
                         class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-white text-xs">
               </div>
               
               <!-- Fair Value Gap -->
               <div class="flex items-center gap-2">
                  <input type="checkbox" v-model="slot.enable_fvg" class="w-3 h-3 accent-purple-500">
                  <label class="text-[10px] text-gray-400">Fair Value Gap</label>
               </div>
               <div>
                  <label class="text-[10px] text-gray-400">FVG Min (ATR)</label>
                  <input type="number" v-model.number="slot.fvg_min_size_atr" step="0.1" min="0.1" max="2" placeholder="0.5"
                         class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-white text-xs">
               </div>
            </div>
         </div>
      </div>

    
      <!-- Action Bar -->
      <div class="pt-3 mt-2 border-t border-gray-700 flex justify-end">
         <button @click="$emit('save', slot)" 
                 class="px-4 py-2 bg-gradient-to-r from-blue-600 to-cyan-600 hover:from-blue-500 hover:to-cyan-500 text-white text-xs font-bold rounded-lg shadow-lg flex items-center gap-2 transition-all transform hover:scale-105 active:scale-95">
           <span>💾</span>
           <span>Save Configuration</span>
         </button>
      </div>

    <!-- Progress / Results -->
    <div class="p-2 border-t border-gray-700">
      <!-- Running - Enhanced Progress Bar -->
      <div v-if="slot.isRunning" class="space-y-1">
        <div class="flex justify-between items-center text-xs">
          <span class="text-blue-300 font-medium flex items-center gap-1">
            <span class="animate-pulse">◉</span>
            Processing...
          </span>
          <span class="text-blue-400 font-bold">{{ slot.progress }}%</span>
        </div>
        <div class="relative w-full bg-gray-700 rounded-full h-2 overflow-hidden">
          <div class="absolute inset-0 bg-gradient-to-r from-blue-600 via-cyan-500 to-blue-600 animate-pulse opacity-20"></div>
          <div class="relative bg-gradient-to-r from-blue-600 to-cyan-500 h-2 rounded-full transition-all duration-500 shadow-lg shadow-blue-500/50"
               :style="{ width: slot.progress + '%' }">
            <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/30 to-white/0 animate-pulse"></div>
          </div>
        </div>
      </div>
      <!-- Results - Enhanced Display -->
      <div v-else-if="slot.results?.win_rate" class="space-y-1">
        <div class="flex justify-between items-center text-xs">
          <span class="font-semibold" :class="slot.results.net_profit >= 0 ? 'text-green-400' : 'text-red-400'">
            {{ slot.results.net_profit >= 0 ? '↑ ' : '↓ ' }}
            {{ slot.results.net_profit >= 0 ? '+' : '' }}${{ slot.results.net_profit?.toFixed(2) }}
          </span>
          <div class="flex items-center gap-2">
            <span class="text-gray-400">WR:</span>
            <span :class="slot.results.win_rate >= 50 ? 'text-green-400 font-semibold' : 'text-yellow-400'">
              {{ slot.results.win_rate?.toFixed(1) }}%
            </span>
          </div>
        </div>
        <div class="flex justify-between text-[10px] text-gray-500">
          <span>{{ slot.results.total_trades || 0 }} trades</span>
          <span v-if="slot.results.profit_factor">
            PF: <span :class="slot.results.profit_factor >= 1.5 ? 'text-green-400' : 'text-yellow-400'">
              {{ slot.results.profit_factor?.toFixed(2) }}
            </span>
          </span>
        </div>
      </div>
      <!-- Ready State -->
      <div v-else class="text-xs text-gray-600 text-center py-1">
        <span class="opacity-50">Ready to trade</span>
      </div>
    </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { SYMBOL_PRESETS } from '@/constants/presets'

const props = defineProps({
  modelValue: {
    type: Object,
    required: true
  }
})

const emit = defineEmits(['update:modelValue', 'save', 'clone', 'delete', 'preset'])

const slot = computed({
  get: () => props.modelValue,
  set: (value) => emit('update:modelValue', value)
})

const presets = SYMBOL_PRESETS

// Helper: Get timeframe in minutes
const getTFMins = (tf) => {
  const map = {
    'M1': 1, 'M5': 5, 'M15': 15, 'M30': 30,
    'H1': 60, 'H4': 240, 'D1': 1440
  }
  return map[tf] || 0
}

// Helper: Check for bad session/symbol combination
const isBadSession = (symbol, session) => {
  if (!symbol || !session) return false
  
  // Asia Session Warnings
  if (session === 'ASIA' || session === 'ASIA_LONDON') {
     // Gold is very low vol in Asia
     if (symbol.includes('XAU')) return true
     // EUR/GBP pairs (non-JPY) are often flat
     if ((symbol.includes('EUR') || symbol.includes('GBP')) && !symbol.includes('JPY')) return true
  }
  return false
}
</script>
