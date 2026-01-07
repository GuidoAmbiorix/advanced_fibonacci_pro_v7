<template>
  <div class="slot-grid-container">
    <!-- Grid Controls -->
    <div class="grid-controls">
      <div class="layout-selector">
        <button
          v-for="layout in layouts"
          :key="layout.id"
          @click="selectedLayout = layout.id"
          :class="['layout-btn', { active: selectedLayout === layout.id }]"
        >
          <component :is="layout.icon" class="w-5 h-5" />
          <span class="text-xs">{{ layout.label }}</span>
        </button>
      </div>

      <div class="slot-selector">
        <label class="text-sm text-gray-400">Slots to Display:</label>
        <div class="slot-checkboxes">
          <label
            v-for="slot in availableSlots"
            :key="slot.id"
            class="slot-checkbox"
          >
            <input
              type="checkbox"
              :value="slot.id"
              v-model="selectedSlots"
              :disabled="selectedSlots.length >= maxSlots && !selectedSlots.includes(slot.id)"
            />
            <span>{{ slot.symbol }} ({{ slot.timeframe }})</span>
            <span
              class="status-dot"
              :class="{
                'bg-green-500': slot.enabled,
                'bg-gray-500': !slot.enabled
              }"
            ></span>
          </label>
        </div>
      </div>

      <button @click="saveGridConfig" class="save-btn">
        Save Configuration
      </button>
    </div>

    <!-- Slot Grid -->
    <div
      class="slot-grid"
      :class="`grid-${selectedLayout}`"
    >
      <MiniSlotCard
        v-for="slotId in selectedSlots.slice(0, maxSlots)"
        :key="slotId"
        :slot-id="slotId"
        @expand="expandSlot"
      />
    </div>

    <!-- Expanded Slot Modal (Configuration Editor) -->
    <div v-if="expandedSlotId" class="expanded-slot-modal" @click.self="expandedSlotId = null">
      <div class="modal-content" @click.stop>
        <div class="flex justify-between items-center mb-6">
          <h3 class="text-xl font-bold text-white flex items-center">
            <span class="mr-2">⚙️</span> Configure {{ editingSlot.symbol }}
          </h3>
          <button @click="expandedSlotId = null" class="text-gray-400 hover:text-white">
            ✖
          </button>
        </div>

        <!-- Tabs -->
        <div class="flex space-x-2 border-b border-gray-700 mb-6 overflow-x-auto pb-2">
            <button v-for="tab in tabs" :key="tab.id"
                @click="currentTab = tab.id"
                :class="['px-3 py-2 text-sm font-medium rounded-t-lg transition-colors whitespace-nowrap', 
                         currentTab === tab.id ? 'bg-gray-700 text-blue-400 border-b-2 border-blue-400' : 'text-gray-400 hover:text-gray-300 hover:bg-gray-800']">
                {{ tab.label }}
            </button>
        </div>

        <!-- Form Content -->
        <div class="overflow-y-auto max-h-[60vh] pr-2 custom-scrollbar">
            
            <!-- 1. GENERAL & RISK -->
            <div v-if="currentTab === 'general'" class="space-y-6">
                <div class="grid grid-cols-2 gap-4">
                    <div class="form-group">
                        <label>Symbol</label>
                        <input v-model="editingSlot.symbol" type="text" class="input-field" disabled />
                    </div>
                    <div class="form-group">
                        <label>Timeframe</label>
                         <select v-model="editingSlot.timeframe" class="input-field">
                            <option value="M1">M1</option><option value="M5">M5</option><option value="M15">M15</option>
                            <option value="H1">H1</option><option value="H4">H4</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Direction</label>
                        <select v-model="editingSlot.direction_filter" class="input-field">
                            <option value="BOTH">Both (Long & Short)</option>
                            <option value="LONG">Long Only</option>
                            <option value="SHORT">Short Only</option>
                        </select>
                    </div>
                     <div class="form-group">
                        <label>Status</label>
                        <div class="flex items-center space-x-2 mt-2">
                            <input v-model="editingSlot.enabled" type="checkbox" class="toggle-checkbox" />
                            <span :class="editingSlot.enabled ? 'text-green-400' : 'text-gray-500'">{{ editingSlot.enabled ? 'ENABLED' : 'DISABLED' }}</span>
                        </div>
                    </div>
                </div>

                <div class="section-title">Risk Management 💰</div>
                <div class="grid grid-cols-3 gap-4">
                    <div class="form-group">
                        <label>Risk %</label>
                        <input v-model.number="editingSlot.risk_percent" type="number" step="0.1" class="input-field" />
                    </div>
                    <div class="form-group">
                         <label>TP Ratio (R)</label>
                        <input v-model.number="editingSlot.tp_ratio" type="number" step="0.1" class="input-field" />
                    </div>
                    <div class="form-group">
                         <label>SL Multiplier (ATR)</label>
                        <input v-model.number="editingSlot.sl_atr_multiplier" type="number" step="0.1" class="input-field" />
                    </div>
                </div>
            </div>

            <!-- 2. SESSION & BIAS -->
            <div v-if="currentTab === 'session'" class="space-y-6">
                <div class="p-4 bg-blue-900/20 border border-blue-800 rounded-lg">
                    <h4 class="text-blue-400 font-bold mb-4">Trading Session 🕒</h4>
                    <div class="form-group">
                        <label>Session Mode</label>
                        <select v-model="editingSlot.trading_session" class="input-field bg-gray-900 border-blue-500/50">
                            <option value="ALL">🟢 ALL (24/7)</option>
                            <option value="LONDON_KZ">🔴 London Only (07-10 UTC)</option>
                            <option value="NY_KZ">🔵 New York Only (12-15 UTC)</option>
                            <option value="BOTH_KZ">🟣 Both (London + NY)</option>
                        </select>
                        <p class="text-xs text-gray-400 mt-1">
                            Current: <span class="text-white font-bold">{{ editingSlot.trading_session }}</span>. 
                            Select "ALL" to trade during the gap (10:00-12:00 UTC).
                        </p>
                    </div>
                </div>

                <div class="grid grid-cols-2 gap-4">
                     <div class="form-group">
                        <label>Session End Action</label>
                        <select v-model="editingSlot.session_end_action" class="input-field">
                            <option value="HOLD">Hold Trades</option>
                            <option value="CLOSE">Close All</option>
                            <option value="BE">Move to Breakeven</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Daily Bias Filter</label>
                        <div class="flex items-center space-x-2 mt-2">
                             <input v-model="editingSlot.use_daily_bias" type="checkbox" class="toggle-checkbox" />
                             <span class="text-sm text-gray-300">Align with Higher Timeframe</span>
                        </div>
                    </div>
                </div>
            </div>

            <!-- 3. INDICATORS -->
            <div v-if="currentTab === 'indicators'" class="space-y-6">
                <div class="grid grid-cols-3 gap-4">
                    <div class="col-span-3 section-title">RSI</div>
                    <div class="form-group">
                        <label>Period</label>
                        <input v-model.number="editingSlot.rsi_period" type="number" class="input-field" />
                    </div>
                    <div class="form-group">
                        <label>Overbought</label>
                        <input v-model.number="editingSlot.rsi_overbought" type="number" class="input-field" />
                    </div>
                     <div class="form-group">
                        <label>Oversold</label>
                        <input v-model.number="editingSlot.rsi_oversold" type="number" class="input-field" />
                    </div>

                    <div class="col-span-3 section-title mt-2">MACD</div>
                    <div class="form-group">
                        <label>Fast</label>
                        <input v-model.number="editingSlot.macd_fast" type="number" class="input-field" />
                    </div>
                     <div class="form-group">
                        <label>Slow</label>
                         <input v-model.number="editingSlot.macd_slow" type="number" class="input-field" />
                    </div>
                     <div class="form-group">
                        <label>Signal</label>
                         <input v-model.number="editingSlot.macd_signal" type="number" class="input-field" />
                    </div>
                </div>
            </div>

            <!-- 4. STRATEGY -->
            <div v-if="currentTab === 'strategy'" class="space-y-4">
                <div class="p-3 bg-gray-700/50 rounded flex justify-between items-center">
                    <span class="font-medium">Enable VWAP Scalp</span>
                    <input v-model="editingSlot.enable_vwap_strategy" type="checkbox" class="toggle-checkbox" />
                </div>
                 <div class="p-3 bg-gray-700/50 rounded flex justify-between items-center">
                    <span class="font-medium">Enable Stoch Momentum</span>
                    <input v-model="editingSlot.enable_stoch_strategy" type="checkbox" class="toggle-checkbox" />
                </div>
                 <div class="p-3 bg-gray-700/50 rounded flex justify-between items-center">
                    <span class="font-medium text-yellow-400">Enable Institutional Sweep 💎</span>
                    <input v-model="editingSlot.enable_institutional_strategy" type="checkbox" class="toggle-checkbox" />
                </div>
                 <div class="p-3 bg-gray-700/50 rounded flex justify-between items-center">
                    <span class="font-medium text-green-400">Enable Fibonacci 📐</span>
                    <input v-model="editingSlot.enable_fibonacci_strategy" type="checkbox" class="toggle-checkbox" />
                </div>
                
                <div class="border-t border-gray-700 my-4"></div>
                
                 <div class="p-3 bg-gray-700/50 rounded flex justify-between items-center">
                    <span class="font-medium">Use ADX Filter (>25)</span>
                    <input v-model="editingSlot.use_adx_filter" type="checkbox" class="toggle-checkbox" />
                </div>
                
                <div class="form-group mt-4">
                     <label>Min Confluence Score ({{ editingSlot.min_confluence_score }})</label>
                     <input v-model.number="editingSlot.min_confluence_score" type="range" min="3" max="10" class="w-full" />
                </div>
            </div>

            <!-- 5. SMC & STRUCTURE -->
            <div v-if="currentTab === 'smc'" class="space-y-6">
                <div class="grid grid-cols-2 gap-4">
                     <div class="form-group">
                        <label>ZigZag Lookback</label>
                        <input v-model.number="editingSlot.zigzag_lookback" type="number" class="input-field" />
                    </div>
                     <div class="form-group">
                        <label>Liquidity Sweep Lookback</label>
                        <input v-model.number="editingSlot.sweep_lookback" type="number" class="input-field" />
                    </div>
                </div>

                <div class="space-y-3">
                    <div class="p-3 bg-gray-700/50 rounded flex justify-between items-center">
                        <span class="font-medium">Enable Order Blocks</span>
                        <input v-model="editingSlot.enable_order_blocks" type="checkbox" class="toggle-checkbox" />
                    </div>
                    <div class="p-3 bg-gray-700/50 rounded flex justify-between items-center">
                        <span class="font-medium">Enable Liquidity Sweeps</span>
                        <input v-model="editingSlot.enable_liquidity_sweep" type="checkbox" class="toggle-checkbox" />
                    </div>
                     <div class="p-3 bg-gray-700/50 rounded flex justify-between items-center">
                        <span class="font-medium">Enable FVG (Fair Value Gaps)</span>
                        <input v-model="editingSlot.enable_fvg" type="checkbox" class="toggle-checkbox" />
                    </div>
                </div>
            </div>

            <!-- 6. MANAGEMENT -->
             <div v-if="currentTab === 'management'" class="space-y-6">
                <div class="form-group">
                    <label>Trailing SL Mode</label>
                    <select v-model="editingSlot.tsl_mode" class="input-field">
                        <option value="FIXED">Fixed Distance</option>
                        <option value="ATR">ATR Dynamic</option>
                        <option value="TIERED">Tiered Profit</option>
                    </select>
                </div>

                 <div class="p-4 bg-gray-700/30 rounded border border-gray-600">
                    <div class="flex items-center justify-between mb-2">
                        <label class="font-bold">Partial Take Profit</label>
                        <input v-model="editingSlot.partial_tp_on" type="checkbox" class="toggle-checkbox" />
                    </div>
                    <div v-if="editingSlot.partial_tp_on">
                        <label class="text-xs text-gray-400">Amount (0.1 - 1.0)</label>
                        <input v-model.number="editingSlot.partial_tp_amount" type="number" step="0.1" max="1" class="input-field mt-1" />
                        <p class="text-xs text-gray-500 mt-1">e.g. 0.5 = Close 50% at TP1</p>
                    </div>
                </div>
            </div>

        </div>

        <!-- Footer Actions -->
        <div class="flex justify-end gap-3 mt-6 pt-4 border-t border-gray-700">
          <button @click="expandedSlotId = null" class="px-4 py-2 text-gray-300 hover:text-white transition-colors">
            Cancel
          </button>
          <button @click="saveSlotConfig" class="px-6 py-2 bg-blue-600 hover:bg-blue-500 text-white font-bold rounded shadow-lg transition-colors flex items-center">
             <span class="mr-2">💾</span> Save Configuration
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { Squares2X2Icon, ViewColumnsIcon, TableCellsIcon } from '@heroicons/vue/24/outline'
import MiniSlotCard from './MiniSlotCard.vue'
import axios from 'axios'

interface Layout {
  id: '2x2' | '3x3' | '4x4' | '2x3'
  label: string
  icon: any
  maxSlots: number
}

const layouts: Layout[] = [
  { id: '2x2', label: '2×2', icon: Squares2X2Icon, maxSlots: 4 },
  { id: '2x3', label: '2×3', icon: ViewColumnsIcon, maxSlots: 6 },
  { id: '3x3', label: '3×3', icon: TableCellsIcon, maxSlots: 9 }
]

const selectedLayout = ref<'2x2' | '3x3' | '4x4' | '2x3'>('2x2')
const selectedSlots = ref<number[]>([])
const expandedSlotId = ref<number | null>(null)
const availableSlots = ref<any[]>([])
const editingSlot = ref<any>({})

const currentTab = ref('session')
const tabs = [
    { id: 'general', label: 'General' },
    { id: 'session', label: 'Session & Bias' },
    { id: 'indicators', label: 'Indicators' },
    { id: 'strategy', label: 'Strategy' },
    { id: 'smc', label: 'SMC' },
    { id: 'management', label: 'Manage' }
]

const maxSlots = computed(() => {
  return layouts.find(l => l.id === selectedLayout.value)?.maxSlots || 4
})

onMounted(async () => {
  await loadSlots()
})

async function loadSlots() {
  try {
    const response = await axios.get('/api/slots')
    availableSlots.value = response.data
    // Auto-select first 4 slots if empty
    if (selectedSlots.value.length === 0) {
        selectedSlots.value = availableSlots.value.slice(0, 4).map(s => s.id)
    }
  } catch (error) {
    console.error('Failed to load slots:', error)
  }
}

function expandSlot(slotId: number) {
  const slot = availableSlots.value.find(s => s.id === slotId)
  if (slot) {
      // Deep copy to editingSlot
      editingSlot.value = JSON.parse(JSON.stringify(slot))
      // Default to session tab for convenience
      currentTab.value = 'session' 
      expandedSlotId.value = slotId
  }
}

async function saveSlotConfig() {
  if (!editingSlot.value || !editingSlot.value.id) return
  
  try {
    await axios.put(`/api/slots/${editingSlot.value.id}`, editingSlot.value)
    alert('✅ Slot Configuration Saved!')
    await loadSlots() // Refresh data
    expandedSlotId.value = null // Close modal
  } catch (error) {
    console.error('Failed to save slot:', error)
    alert('❌ Failed to save configuration. Check console.')
  }
}

async function saveGridConfig() {
  try {
    await axios.post('/api/grid-configs', {
      name: 'My Grid',
      layout: selectedLayout.value,
      slot_ids: selectedSlots.value,
      show_stats: true,
      show_signals: true,
      auto_refresh_interval: 5
    })
    alert('Grid configuration saved!')
  } catch (error) {
    console.error('Failed to save grid config:', error)
    alert('Failed to save configuration')
  }
}
</script>

<style scoped>
.grid-controls {
  @apply bg-gray-800 p-4 rounded-lg mb-4 space-y-4;
}

.layout-selector {
  @apply flex gap-2;
}

.layout-btn {
  @apply flex items-center gap-2 px-4 py-2 bg-gray-700 rounded hover:bg-gray-600 transition-colors text-gray-300;
}

.layout-btn.active {
  @apply bg-blue-600 text-white;
}

.slot-checkboxes {
  @apply grid grid-cols-2 gap-2 mt-2;
}

.slot-checkbox {
  @apply flex items-center gap-2 text-sm text-gray-300;
}

.status-dot {
  @apply w-2 h-2 rounded-full;
}

.slot-grid {
  @apply grid gap-4;
}

.grid-2x2 {
  @apply grid-cols-2 grid-rows-2;
}

.grid-2x3 {
  @apply grid-cols-2 grid-rows-3;
}

.grid-3x3 {
  @apply grid-cols-3 grid-rows-3;
}

.save-btn {
  @apply bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded text-sm font-medium text-white;
}

.expanded-slot-modal {
  @apply fixed inset-0 bg-black/80 flex items-center justify-center z-50 backdrop-blur-sm;
}

.modal-content {
  @apply bg-gray-900 border border-gray-700 rounded-xl p-6 w-full max-w-3xl mx-4 shadow-2xl;
}

/* Form Styling */
.form-group {
    @apply flex flex-col;
}

label {
    @apply text-xs font-bold text-gray-400 uppercase mb-1 tracking-wider;
}

.input-field {
    @apply bg-gray-800 border border-gray-600 rounded px-3 py-2 text-white text-sm focus:border-blue-500 focus:outline-none transition-colors;
}

.toggle-checkbox {
    @apply w-5 h-5 text-blue-600 bg-gray-700 border-gray-600 rounded focus:ring-blue-600 ring-offset-gray-800;
}

.section-title {
    @apply text-sm font-bold text-white border-b border-gray-700 pb-1 mb-2;
}
</style>


