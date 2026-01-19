<template>
  <div class="group relative overflow-hidden rounded-xl border transition-all duration-300"
       :class="slot.isRunning
         ? 'bg-gradient-to-br from-blue-900/40 to-purple-900/40 border-blue-400/50 shadow-xl'
         : slot.enabled
         ? 'bg-gradient-to-br from-slate-800/90 to-slate-900/90 border-slate-600/50 shadow-lg hover:shadow-xl hover:border-slate-500/60'
         : 'bg-gray-900/60 border-gray-700/50 opacity-70'">

    <!-- Animated border for running slots -->
    <div v-if="slot.isRunning" class="absolute inset-0 pointer-events-none">
      <div class="absolute inset-0 bg-gradient-to-r from-blue-500/20 via-purple-500/20 to-blue-500/20 animate-pulse"></div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- HEADER                                                                   -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <div class="p-4 border-b border-slate-700/50">
      <div class="flex items-center justify-between">
        <!-- Left: Toggle & Title -->
        <div class="flex items-center gap-3">
          <!-- Modern Toggle Switch -->
          <button
            @click="toggleEnabled"
            :disabled="slot.isRunning"
            class="relative w-12 h-6 rounded-full transition-all"
            :class="[
              slot.enabled 
                ? 'bg-gradient-to-r from-blue-500 to-cyan-500' 
                : 'bg-gray-700',
              slot.isRunning ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer hover:shadow-lg'
            ]"
          >
            <div 
              class="absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full transition-transform flex items-center justify-center shadow-md"
              :class="slot.enabled ? 'translate-x-6' : ''"
            >
              <svg v-if="slot.enabled" class="w-3 h-3 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"></path>
              </svg>
            </div>
          </button>

          <div>
            <div class="flex items-center gap-2">
              <h3 class="font-bold" :class="slot.enabled ? 'text-white' : 'text-gray-400'">
                Slot {{ slot.id + 1 }}
              </h3>
              <!-- Running Status Badge -->
              <span v-if="slot.isRunning" class="flex items-center gap-1.5 px-2 py-0.5 bg-blue-500/20 rounded-full text-xs text-blue-300 border border-blue-400/30">
                <div class="w-1.5 h-1.5 bg-blue-400 rounded-full animate-pulse"></div>
                Processing {{ slot.progress }}%
              </span>
            </div>
            <!-- Session Warning -->
            <div v-if="validation.sessionWarning" class="flex items-center gap-1 mt-1 text-xs text-yellow-400">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
              </svg>
              <span>Low volatility expected for this session</span>
            </div>
          </div>
        </div>

        <!-- Right: Actions -->
        <div class="flex items-center gap-1">
          <button @click="$emit('clone', slot)"
                  :disabled="slot.isRunning"
                  class="p-2 rounded-lg hover:bg-blue-500/10 text-blue-400 hover:text-blue-300 transition-colors disabled:opacity-30"
                  title="Clone Configuration">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
            </svg>
          </button>
          <button @click="slot.expanded = !slot.expanded"
                  class="p-2 rounded-lg hover:bg-slate-700/50 text-gray-400 hover:text-white transition-colors">
            <svg class="w-4 h-4 transition-transform" :class="slot.expanded ? 'rotate-180' : ''" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
            </svg>
          </button>
          <button @click="$emit('delete', slot.id)"
                  :disabled="slot.isRunning"
                  class="p-2 rounded-lg hover:bg-red-500/10 text-red-400 hover:text-red-300 transition-colors disabled:opacity-30"
                  title="Delete Slot">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
            </svg>
          </button>
        </div>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- COMPACT SUMMARY (Always Visible)                                         -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <div class="p-4 space-y-3">
      <!-- Symbol & Direction Row -->
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-xs text-gray-400 mb-1.5">Trading Pair</label>
          <select v-model="slot.symbol" :disabled="!slot.enabled"
                  @change="$emit('preset', slot)"
                  class="w-full bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-white text-sm disabled:opacity-50 focus:outline-none focus:ring-2 focus:ring-blue-500/50">
            <option v-for="(preset, sym) in presets" :key="sym" :value="sym">
              {{ preset.emoji }} {{ preset.name }}
            </option>
          </select>
          <div class="mt-1 flex items-center justify-between">
            <span class="text-xs text-gray-500">{{ presets[slot.symbol]?.description }}</span>
            <span class="text-[10px] px-1.5 py-0.5 rounded border"
                  :class="volatilityClass">
              {{ presets[slot.symbol]?.volatility }}
            </span>
          </div>
        </div>

        <div>
          <label class="block text-xs text-gray-400 mb-1.5">Direction</label>
          <select v-model="slot.direction" :disabled="!slot.enabled"
                  class="w-full bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-sm disabled:opacity-50 focus:outline-none focus:ring-2 focus:ring-blue-500/50"
                  :class="directionClass">
            <option value="BOTH">↕️ Both Directions</option>
            <option value="BUY_ONLY">🟢 Long Only</option>
            <option value="SELL_ONLY">🔴 Short Only</option>
          </select>
        </div>
      </div>

      <!-- Results / Progress Bar -->
      <div v-if="slot.isRunning" class="space-y-2">
        <div class="relative w-full bg-slate-700/50 rounded-full h-2 overflow-hidden">
          <div class="absolute h-full bg-gradient-to-r from-blue-500 to-cyan-400 transition-all duration-500"
               :style="{ width: slot.progress + '%' }">
            <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/30 to-white/0 animate-pulse"></div>
          </div>
        </div>
      </div>
      
      <div v-else-if="slot.results?.win_rate" class="grid grid-cols-3 gap-3 p-3 bg-slate-800/50 rounded-lg border border-slate-700/50">
        <div class="text-center">
          <div class="text-lg font-bold" :class="slot.results.net_profit >= 0 ? 'text-green-400' : 'text-red-400'">
            {{ slot.results.net_profit >= 0 ? '+' : '' }}${{ slot.results.net_profit?.toFixed(0) }}
          </div>
          <div class="text-xs text-gray-400">P&L</div>
        </div>
        <div class="text-center">
          <div class="text-lg font-bold" :class="slot.results.win_rate >= 50 ? 'text-green-400' : 'text-yellow-400'">
            {{ slot.results.win_rate?.toFixed(1) }}%
          </div>
          <div class="text-xs text-gray-400">Win Rate</div>
        </div>
        <div class="text-center">
          <div class="text-lg font-bold text-blue-400">{{ slot.results.total_trades || 0 }}</div>
          <div class="text-xs text-gray-400">Trades</div>
        </div>
      </div>
      
      <div v-else class="text-center py-3 text-sm text-gray-500">
        {{ slot.enabled ? '⚡ Ready to trade' : '💤 Disabled' }}
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <!-- EXPANDED CONFIGURATION                                                   -->
    <!-- ═══════════════════════════════════════════════════════════════════════ -->
    <div v-if="slot.expanded && slot.enabled" class="border-t border-slate-700/50 p-4 space-y-4 bg-slate-900/30">
      
      <!-- Core Settings -->
      <div class="space-y-3">
        <h4 class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Core Settings</h4>
        
        <div class="grid grid-cols-3 gap-3">
          <div>
            <label class="block text-xs text-gray-400 mb-1.5">Timeframe</label>
            <select v-model="slot.timeframe"
                    class="w-full bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/50">
              <option value="M1">1 Minute</option>
              <option value="M5">5 Minutes</option>
              <option value="M15">15 Minutes</option>
              <option value="H1">1 Hour</option>
              <option value="H4">4 Hours</option>
            </select>
          </div>

          <div>
            <label class="block text-xs text-gray-400 mb-1.5 flex items-center gap-1">
              Confirmation TF
              <div class="group relative">
                <svg class="w-3 h-3 cursor-help text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <div class="hidden group-hover:block absolute z-10 w-48 p-2 bg-slate-800 border border-slate-600 rounded text-xs text-gray-300 -top-2 left-5 shadow-xl">
                  Higher timeframe for trend confirmation. Must be ≥ entry timeframe.
                </div>
              </div>
            </label>
            <select v-model="slot.confirmation_timeframe"
                    class="w-full bg-slate-800 border rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:ring-2"
                    :class="validation.confirmTFValid 
                      ? 'border-slate-600 focus:ring-blue-500/50' 
                      : 'border-red-500 focus:ring-red-500/50'">
              <option :value="null">Auto (Same as TF)</option>
              <option value="M5">5 Minutes</option>
              <option value="M15">15 Minutes</option>
              <option value="H1">1 Hour</option>
              <option value="H4">4 Hours</option>
            </select>
          </div>

          <div>
            <label class="block text-xs text-gray-400 mb-1.5">Trailing Stop</label>
            <select v-model="slot.tsl_mode"
                    class="w-full bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/50">
              <option value="OFF">Disabled</option>
              <option value="ATR">ATR-Based</option>
              <option value="TIERED">Tiered Profit</option>
            </select>
          </div>
        </div>

        <!-- Risk Management with Sliders -->
        <div class="grid grid-cols-3 gap-3">
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <label class="text-xs text-gray-400">Position Size</label>
              <select v-model="slot.volume_mode"
                      class="bg-slate-700 text-xs rounded px-2 py-0.5 text-blue-300 border-none">
                <option value="RISK">% Risk</option>
                <option value="FIXED">Fixed Lots</option>
              </select>
            </div>
            <template v-if="slot.volume_mode === 'FIXED'">
              <input type="number" v-model.number="slot.fixed_volume"
                     step="0.01" min="0.01"
                     class="w-full bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-cyan-300 font-bold text-sm focus:outline-none focus:ring-2 focus:ring-cyan-500/50">
            </template>
            <template v-else>
              <div class="space-y-1">
                <input type="range" v-model.number="slot.risk_percent"
                       min="0.1" max="5" step="0.1"
                       class="w-full accent-blue-500">
                <div class="text-sm font-bold text-center" :class="riskLevelClass">
                  {{ slot.risk_percent }}%
                </div>
              </div>
            </template>
          </div>

          <div>
            <label class="block text-xs text-gray-400 mb-1.5">Take Profit (R)</label>
            <div class="space-y-1">
              <input type="range" v-model.number="slot.tp_ratio"
                     min="1" max="5" step="0.5"
                     class="w-full accent-green-500">
              <div class="text-sm font-bold text-center text-green-400">
                {{ slot.tp_ratio }}R
              </div>
            </div>
          </div>

          <div>
            <label class="block text-xs text-gray-400 mb-1.5">Stop Loss (ATR)</label>
            <div class="space-y-1">
              <input type="range" v-model.number="slot.sl_atr_multiplier"
                     min="0.5" max="3" step="0.5"
                     class="w-full accent-red-500">
              <div class="text-sm font-bold text-center text-red-400">
                {{ slot.sl_atr_multiplier }}× ATR
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Session Controls -->
      <div class="p-3 bg-blue-900/10 rounded-lg border border-blue-500/20 space-y-3">
        <h4 class="text-xs font-semibold text-blue-300 uppercase tracking-wider flex items-center gap-2">
          🏛️ Session Management
        </h4>
        
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-xs text-gray-400 mb-1.5">Trading Session</label>
            <select v-model="slot.session_mode"
                    class="w-full bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/50">
              <option value="BOTH_KZ">🎯 London + NY Killzones</option>
              <option value="LONDON_KZ">🇬🇧 London Only</option>
              <option value="NY_KZ">🇺🇸 NY Only</option>
              <option value="OVERLAP_KZ">⚡ Overlap Only</option>
              <option value="ALL">🌍 All Sessions</option>
            </select>
          </div>

          <div>
            <label class="block text-xs text-gray-400 mb-1.5">Session End Action</label>
            <select v-model="slot.session_end_action"
                    class="w-full bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500/50">
              <option value="HOLD">✋ Hold Positions</option>
              <option value="CLOSE">❌ Close All</option>
              <option value="DISABLE_NEW">⛔ Block New Entries</option>
            </select>
          </div>
        </div>

        <label class="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" v-model="slot.use_daily_bias"
                 class="w-4 h-4 rounded bg-slate-700 border-slate-600 text-blue-500 focus:ring-blue-500 focus:ring-offset-slate-900">
          <span class="text-sm text-gray-300">Filter with Daily Trend (D1 Bias)</span>
        </label>
      </div>

      <!-- Advanced Settings Toggle -->
      <button @click="showAdvanced = !showAdvanced"
              class="w-full py-2 px-3 bg-slate-800/50 hover:bg-slate-800 border border-slate-600 rounded-lg text-sm text-gray-300 flex items-center justify-between transition-colors">
        <span>Advanced Indicators & SMC</span>
        <svg class="w-4 h-4 transition-transform" :class="showAdvanced ? 'rotate-180' : ''" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
        </svg>
      </button>

      <!-- Advanced Settings Panel -->
      <div v-if="showAdvanced" class="space-y-3 animate-fadeIn">
        <!-- MACD -->
        <div class="p-3 bg-yellow-900/10 rounded-lg border border-yellow-600/30">
          <h5 class="text-xs font-semibold text-yellow-400 uppercase tracking-wider mb-2">⚡ MACD Momentum</h5>
          <div class="grid grid-cols-3 gap-2">
            <div>
              <label class="block text-xs text-gray-400 mb-1">Fast</label>
              <input type="number" v-model.number="slot.config.macd_fast" placeholder="8"
                     class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-white text-sm">
            </div>
            <div>
              <label class="block text-xs text-gray-400 mb-1">Slow</label>
              <input type="number" v-model.number="slot.config.macd_slow" placeholder="21"
                     class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-white text-sm">
            </div>
            <div>
              <label class="block text-xs text-gray-400 mb-1">Signal</label>
              <input type="number" v-model.number="slot.config.macd_signal" placeholder="5"
                     class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-white text-sm">
            </div>
          </div>
        </div>

        <!-- RSI -->
        <div class="p-3 bg-purple-900/10 rounded-lg border border-purple-600/30">
          <h5 class="text-xs font-semibold text-purple-400 uppercase tracking-wider mb-2">📊 RSI Value</h5>
          <div class="grid grid-cols-3 gap-2">
            <div>
              <label class="block text-xs text-gray-400 mb-1">Period</label>
              <input type="number" v-model.number="slot.config.rsi_period" placeholder="14"
                     class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-white text-sm">
            </div>
            <div>
              <label class="block text-xs text-gray-400 mb-1">Buy ≤</label>
              <input type="number" v-model.number="slot.config.rsi_buy_threshold" placeholder="45"
                     class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-green-300 text-sm">
            </div>
            <div>
              <label class="block text-xs text-gray-400 mb-1">Sell ≥</label>
              <input type="number" v-model.number="slot.config.rsi_sell_threshold" placeholder="55"
                     class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-red-300 text-sm">
            </div>
          </div>
        </div>

        <!-- Structure (ZigZag) -->
        <div class="p-3 bg-blue-900/10 rounded-lg border border-blue-500/20">
          <h5 class="text-xs font-semibold text-blue-400 uppercase tracking-wider mb-2">🛡️ Structure (v3.0)</h5>
          <div>
            <label class="block text-xs text-gray-400 mb-1">ZigZag Lookback (Recommended: 12)</label>
            <input type="number" v-model.number="slot.zigzag_lookback" min="3" max="20" placeholder="12"
                   class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-white text-sm">
          </div>
        </div>

        <!-- Smart Money Concepts -->
        <div class="p-3 bg-purple-900/10 rounded-lg border border-purple-500/20">
          <h5 class="text-xs font-semibold text-purple-400 uppercase tracking-wider mb-3">🧠 Smart Money Concepts</h5>
          <div class="space-y-2">
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" v-model="slot.enable_order_blocks"
                     class="w-4 h-4 rounded bg-slate-700 border-slate-600 text-purple-500">
              <span class="text-sm text-gray-300">Order Blocks</span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" v-model="slot.enable_liquidity_sweep"
                     class="w-4 h-4 rounded bg-slate-700 border-slate-600 text-purple-500">
              <span class="text-sm text-gray-300">Liquidity Sweep Detection</span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" v-model="slot.enable_fvg"
                     class="w-4 h-4 rounded bg-slate-700 border-slate-600 text-purple-500">
              <span class="text-sm text-gray-300">Fair Value Gaps</span>
            </label>
          </div>
        </div>
      </div>

      <!-- Save Button -->
      <div class="pt-4 border-t border-slate-700/50">
        <button @click="handleSave"
                class="w-full py-3 bg-gradient-to-r from-blue-600 to-cyan-600 hover:from-blue-500 hover:to-cyan-500 text-white font-semibold rounded-lg shadow-lg flex items-center justify-center gap-2 transition-all transform hover:scale-[1.02] active:scale-[0.98]">
          <template v-if="saveStatus === 'saving'">
            <div class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"></div>
            <span>Saving...</span>
          </template>
          <template v-else-if="saveStatus === 'saved'">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
            </svg>
            <span>Saved Successfully!</span>
          </template>
          <template v-else>
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"></path>
            </svg>
            <span>Save Configuration</span>
          </template>
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { SYMBOL_PRESETS } from '@/constants/presets'

const props = defineProps({
  modelValue: {
    type: Object,
    required: true
  }
})

const emit = defineEmits(['update:modelValue', 'save', 'clone', 'delete', 'preset'])

// Local state
const showAdvanced = ref(false)
const saveStatus = ref(null)

// Two-way binding for slot
const slot = computed({
  get: () => props.modelValue,
  set: (value) => emit('update:modelValue', value)
})

const presets = SYMBOL_PRESETS

// Validation logic
const validation = computed(() => {
  const confirmTFValid = !slot.value.confirmation_timeframe || 
    getTFMins(slot.value.confirmation_timeframe) >= getTFMins(slot.value.timeframe)
  
  const sessionWarning = isBadSession(slot.value.symbol, slot.value.session_mode)
  
  const riskLevel = slot.value.volume_mode === 'RISK' 
    ? (slot.value.risk_percent > 3 ? 'high' : slot.value.risk_percent > 2 ? 'medium' : 'safe')
    : 'fixed'

  return { confirmTFValid, sessionWarning, riskLevel }
})

// Computed classes
const volatilityClass = computed(() => {
  const vol = presets[slot.value.symbol]?.volatility
  if (vol === 'EXTREME') return 'bg-red-900/30 text-red-400 border-red-500/30'
  if (vol === 'HIGH') return 'bg-orange-900/30 text-orange-400 border-orange-500/30'
  if (vol === 'MEDIUM') return 'bg-yellow-900/30 text-yellow-400 border-yellow-500/30'
  return 'bg-green-900/30 text-green-400 border-green-500/30'
})

const directionClass = computed(() => {
  if (slot.value.direction === 'BUY_ONLY') return 'text-green-400'
  if (slot.value.direction === 'SELL_ONLY') return 'text-red-400'
  return 'text-white'
})

const riskLevelClass = computed(() => {
  if (validation.value.riskLevel === 'high') return 'text-red-400'
  if (validation.value.riskLevel === 'medium') return 'text-yellow-400'
  return 'text-green-400'
})

// Methods
const toggleEnabled = () => {
  if (!slot.value.isRunning) {
    slot.value.enabled = !slot.value.enabled
    emit('save', slot.value)
  }
}

const handleSave = () => {
  saveStatus.value = 'saving'
  emit('save', slot.value)
  setTimeout(() => {
    saveStatus.value = 'saved'
    setTimeout(() => {
      saveStatus.value = null
    }, 2000)
  }, 500)
}

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
  if (session === 'ASIA' || session === 'ASIA_LONDON') {
    if (symbol.includes('XAU')) return true
    if ((symbol.includes('EUR') || symbol.includes('GBP')) && !symbol.includes('JPY')) return true
  }
  return false
}
</script>

<style scoped>
.animate-fadeIn {
  animation: fadeIn 0.3s ease-out;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(-8px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>
